---
name: review
description: "This skill should be used when performing exhaustive code reviews using multi-agent analysis, ultra-thinking, and worktrees."
---

<!-- lifecycle-handoff-protocol:start -->
**Lifecycle handoff (standalone `/review`):** When no parent orchestrator (`one-shot`, `work`) owns the pipeline, invoke `/compound` then `/ship` after review — do not end at the review summary. In pipeline mode, emit the compact `## Review Phase Complete` marker only (see Step 3 pipeline detection).
<!-- lifecycle-handoff-protocol:end -->

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill's engine lives at [`workflows/review.workflow.js`](./workflows/review.workflow.js) — deterministic change-class fan-out, per-finding adversarial verification, and CONCUR-gated filing. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/review/workflows/review.workflow.js", args: "<PR#>" })`. See [`workflows/README.md`](./workflows/README.md). The prose skill below stays the default; the two coexist during calibration.

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
- **Runbook-obligation caller-site sweep:** When a migration adds an `ON DELETE RESTRICT` FK AND a same-PR RPC documented in the migration COMMENT as the cascade pre-step (pattern: `MUST call <rpc_name>` or `runbook MUST call`), the reviewer MUST run `git grep -n '<rpc_name>'` and require at least one match outside `supabase/migrations/`, `knowledge-base/`, and the plan file. The migration's own prose is the STATEMENT of the obligation, not evidence the obligation is satisfied. See [[2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr]] (PR #3853 surfaced this via five concurring agent findings).

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
- **Bash-only PRs (all `.sh`/`.bash`/`.zsh`, no other source extensions):** OSS semgrep's tree-sitter bash parser cannot analyze bash files end-to-end (parses ~100% of lines but matches 0 rules — vacuous "0 findings"). Skip semgrep-sast and substitute `shellcheck` as the deterministic gate. See `knowledge-base/project/learnings/2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` for the bench-pattern session that surfaced this. **Why:** PR #4045 — semgrep-sast on a 1336-line bash diagnostic returned vacuous output that could mislead future readers; shellcheck is the bash-native equivalent.

**Bootstrap (mandatory before spawning the agent):** Run [ensure-semgrep.sh](./scripts/ensure-semgrep.sh) from the repo root. The script checks PATH first, then auto-installs via brew → pipx → `pip --user` in that order. Exits 0 when semgrep is reachable. Exit 1 means an install was attempted and failed; exit 2 means no install path was available (no brew, pipx, or python3 with pip). On non-zero exit, print the script's stderr to the user and abort the review. Do NOT silently skip — the deterministic SAST pass is what catches CodeQL-equivalent patterns like `js/file-system-race` before push.

**Custom rules file:** [semgrep-custom-rules.yaml](./references/semgrep-custom-rules.yaml) ships alongside the public rule packs and covers CodeQL queries the public packs miss (e.g. the TOCTOU patterns that blocked PR #2463 in CI). The semgrep-sast agent loads it via `--config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml`. Extend it whenever a CodeQL finding in CI was not caught locally — the goal is no-surprises on CI. **Run semgrep from the worktree/repo root** — that `--config` path is repo-root-relative, so a persisted `cd apps/web-platform` (left over from a prior `tsc`/`vitest` call; the Bash tool keeps CWD across calls) makes semgrep exit 7 `config path does not exist`. Use `cd <root> && semgrep …` in one call, or pass an absolute `--config`. **Why:** #4742.

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

**If the diff touches a domain-model business-rule surface (#5871):**

17. Domain-model register drift note — run when `git diff main...HEAD --name-only` matches `(^|/)apps/web-platform/supabase/migrations/.*\.sql$`, `(^|/)apps/web-platform/server/workspace-resolver\.ts$`, or `(^|/)knowledge-base/engineering/architecture/domain-model\.md$` (same surface as preflight Check 11). Run `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md` and surface **one informational line** in the review summary: `domain-model register: N stale citation(s), M undocumented table(s) — see /soleur:sync domain-model`. Purely informational — the blocking enforcement is preflight Check 11 (stale-only); the non-redundant value here is the **undocumented-facts** pointer, which the ship gate deliberately does not surface (the register is a curated subset). Never blocks; no coordination logic.

#### Boundary disambiguation — gdpr-gate vs. data-integrity-guardian vs. security-sentinel {#boundaries}

Use `gdpr-gate` for deterministic Art. 9 / RoPA / lawful-basis pattern checks; use `data-integrity-guardian` for migration safety and judgment-based PII review; use `security-sentinel` for OWASP/CWE security-of-processing flaws AND multi-org / workspace boundary integrity (the R1–R6 checklist — RLS routing through `is_workspace_member()`, JWT `current_organization_id` consumption, attestation owner-checks, SECURITY DEFINER `search_path` pinning, write-boundary sentinel on workspace_id-bearing tables). The three reviewers complement each other and may all fire on the same migration PR — each owns a distinct lens. This is the **canonical disambiguation prose**; sibling agent files reference back here as the single source of truth.

### Anti-slop Scanner Hook

**If the diff touches `apps/web-platform/(app|components)/.*\.(tsx|jsx|css)$` OR `apps/web-platform/server/.*\.(ts|tsx)$` OR `plugins/soleur/docs/.*\.(njk|css)$`:**

17. Run the `soleur:frontend-anti-slop` Tier 1 scanner inline (no separate agent spawn — v1 simplification per plan PR #4265). Scope covers the Next.js platform, the server-side email/HTML templates, and the Eleventy marketing site so AI-assisted edits to landing pages, transactional emails, or blog posts get the same audit as React component changes.

    ```bash
    # Keep NUL framing end-to-end. The host `grep` is ugrep, where the NUL-data
    # flag means `--decompress` (NOT GNU `--null-data`) and silently matches
    # zero files (the #4635 false-clean). Do NOT use grep at all in this
    # collector: read the NUL-delimited diff with `read -r -d ''` and match each
    # path against EXT_RE in bash, so filenames containing literal newlines
    # survive intact. The path regex mirrors `DEFAULT_PATH_RE_SOURCE` in
    # tier1-scan.ts (parity-tested).
    EXT_RE='(apps/web-platform/(app|components)/.*\.(tsx|jsx|css)|apps/web-platform/server/.*\.(ts|tsx)|plugins/soleur/docs/.*\.(njk|css))$'
    CHANGED_FILES=()
    HAS_EXT_FILE=0
    while IFS= read -r -d '' f; do
      [[ "$f" =~ $EXT_RE ]] && CHANGED_FILES+=("$f")
      [[ "$f" =~ \.(tsx|jsx|ts|css|njk)$ ]] && HAS_EXT_FILE=1
    done < <(git diff --name-only -z origin/main...HEAD)
    if (( ${#CHANGED_FILES[@]} > 0 )); then
      bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts \
        --paths "${CHANGED_FILES[@]}" --json
    elif (( HAS_EXT_FILE == 1 )); then
      # Guard against silent false-clean: the diff DOES contain scanner-extension
      # files but none matched the scope regex (or the collector mis-fired).
      # Warn loudly instead of reporting clean — this is the #4635 failure class.
      echo "WARNING: diff contains scanner-extension files but none matched the anti-slop scope regex; the scanner did NOT run — verify the path regex / collector did not silently drop files." >&2
    fi
    ```

**What this hook checks:**

- 18 deterministic Tier 1 gates adapted from [Nutlope/hallmark](https://github.com/Nutlope/hallmark) (MIT) — gradient-fill headlines, generic display fonts, purple→blue gradients, `transition-all`, uniform `hover:scale-105`, placeholder names, zero-chroma neutrals, off-scale spacing, prose-width out of range, two-icon-library imports, plus 3 `brand`-category gates (raw hex, white-on-gold contrast, non-zero corners), etc. See [slop-rules.md](../frontend-anti-slop/references/slop-rules.md).
- The anti-slop (non-brand) findings are **advisory and non-blocking** in v1 (calibration mode). They surface in the review output for operator triage; no auto-file to GitHub issues. Promotion to auto-file gates on ≤ 10% FP rate over ≥ 20 findings ≥ 2 weeks (per `soleur:frontend-anti-slop` SKILL.md §"Calibration mode").
- **High-severity `brand` findings are a required-fix gate, NOT operator triage.** When the scanner reports a finding whose originating rule is `category: brand` and `severity: high` (BRAND-RAW-HEX, BRAND-WHITE-ON-GOLD), the scanner exits non-zero (1) — the diff must be fixed before merge, the reviewing agent does not get to narrate it away as a likely false positive. Brand `medium` findings (BRAND-NONZERO-CORNER) stay advisory like the rest.
- Findings conform to `finding.schema.json` with `category: "anti-slop"`, `selector: "<file-path>#<RULE-ID>"`. Pretty-print the JSON array directly into the review output as a fenced code block; the reviewing agent narrates which findings look like true positives.

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

**Workspaces-flag precondition:** When the diff documents an `npm run -w <workspace> <script>` invocation, grep the repo-root `package.json` for `"workspaces"` and refuse the documented form if the field is absent. Without a root `workspaces:` declaration, `npm` aborts with "No workspaces found". The grep is one line; the false-negative cost is an operator runbook that returns the error on first use. **Why:** PR #3751 — see `knowledge-base/project/learnings/2026-05-13-npm-workspaces-flag-fails-without-root-workspaces-declaration.md`.

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

**Cost-of-filing gate (FIRST FILTER — apply BEFORE invoking the CONCUR
second-reviewer gate AND BEFORE evaluating the four scope-out criteria below):**
If the fix is ≤100 lines of code AND touches ≤4 files AND no reviewer agent
independently dissents on technical grounds (e.g., contested-design with named
alternatives), fix inline. The bookkeeping cost of `gh issue create + scope-out
justification + future triage + closure + follow-up PR` averages ~30 minutes of
cumulative human attention, and that cost is **fixed** — it does not shrink
with the size of the deferred fix. The edit cost is what scales: a ≤100-line
edit runs roughly 5–20 minutes. So the two curves cross well above the old
30-line boundary, and everything below the crossover is NET-NEGATIVE work to
file.

**Why 100/4 and not 30/2 (raised 2026-07-20).** The old boundary was set when
filing looked cheap. Measured over the 7 days to 2026-07-20: 269 issues filed
against 132 merged PRs (2.04 filed per PR) and 125 closed, growing the queue
+144/week — up from +7.2/day over the prior 23 days. A 30-line boundary sends
most real findings to the queue, and the queue does not drain. Raising to
≤100 lines AND ≤4 files moves the crossover to where the arithmetic actually
sits. This threshold is **instrumented**, not guessed: every disposition emits
a telemetry row (see the auto-flip below), so the next tuning pass reads data
instead of re-arguing from intuition.

This gate is load-bearing: a PR that opens more issues than it closes is a
workflow failure, not a normal review outcome. That is now enforced rather
than asserted — see the blocking net-issue-flow gate in
[`ship/SKILL.md`](../ship/SKILL.md) and
[`net-issue-flow.sh`](../ship/scripts/net-issue-flow.sh).

**Mechanical pre-CONCUR auto-flip:**

Before invoking `code-simplicity-reviewer`, self-assess fix size. If ≤100 lines AND ≤4 files, BYPASS the CONCUR gate — the disposition is auto-flipped to fix-inline. Apply the fix; do not file.

**Instrumentation (REQUIRED, not optional).** Emit one telemetry row per
finding disposition, so the next threshold tuning reads measured flip-vs-file
ratios instead of re-arguing from intuition. This is the half of the change
that makes the *next* change cheap:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh"
# DISPOSITION is exactly one of: flip-inline | file
emit_incident "cost-of-filing-${DISPOSITION}" applied \
  "review disposition: ${DISPOSITION} (${LINES} lines, ${FILES} files)"
```

The disposition rides in the **`rule_id`** (`cost-of-filing-flip-inline` vs
`cost-of-filing-file`) and the event stays `applied`. That is not a stylistic
choice: the `rule-metrics-aggregate.sh` report keys every counter on `rule_id` and
gates on `event_type ∈ {deny,bypass,applied,warn}` — it **never reads `.kind`**,
so a `kind`-based scheme would write rows that no report ever surfaces. Read the
resulting ratio with `bash scripts/rule-metrics-aggregate.sh` and compare the
two `applied_count` values.

If the fix size cannot be confidently bounded without writing it, write a 5-minute spike. If the spike exceeds 100 lines, run CONCUR; if it doesn't, commit the spike. Do NOT run CONCUR on a fix you've already written and verified to be small.

The gate fails (fix-inline is required) when:

- Fix is ≤100 lines AND ≤4 files, regardless of "feels like a follow-up" framing.
- The only objection to fixing inline is bookkeeping/scope discipline (vs. a
    concrete technical contest the agent named).
- The finding is `pr-introduced` (per Step 1 provenance triage) — these always
    fix inline.
- The finding is "X is missing from sibling artifact Y" AND this PR's diff is the
    surface that introduces `X` into the sibling set for the first time — the
    asymmetry is `pr-introduced` regardless of when X's underlying capability
    shipped. Mechanical test: `git diff origin/main --name-only | xargs grep -l
    "<X>"` against the sibling set on `main`. If `main` had zero `X` mentions
    across {A, B, C} and this PR adds `X` to A only, the asymmetry between
    A-present and (B, C)-silent is created by this PR. The `pre-existing-unrelated`
    scope-out criterion fails; fix inline. **Why:** PR #3755 (#3708) tried to file
    gdpr-policy/privacy-policy Sentry-gap as `pre-existing-unrelated`;
    `code-simplicity-reviewer` DISSENTed precisely on this rule. See
    `knowledge-base/project/learnings/2026-05-14-discrete-enumeration-relockstep-and-pr-introduced-asymmetry.md`.

The gate may pass (proceed to evaluate the four scope-out criteria) when:

- Fix is >100 lines OR touches >4 files, AND
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

**Auto-wire deferred-scope-outs into the follow-through sweeper.** When a
scope-out passes the CONCUR gate AND its `Re-eval by:` trigger is a concrete
date / dependency / event-grep / counter form, the filing ALSO wires the issue
into the follow-through auto-close substrate so it cannot rot open past its
trigger:

1. add `--label follow-through` to the `gh issue create` call (alongside
   `--label deferred-scope-out`);
2. scaffold a verification script named `<slug>-<issue-or-pr>.sh` under the
   followthroughs directory by `cp`-ing the
   [stub template](../ship/references/followthrough-stub-template.sh) and
   replacing the TODO body with the exit-code probe for the trigger shape
   (mapping in [review-todo-structure.md](./references/review-todo-structure.md)
   §Re-evaluation Trigger), then `chmod +x`;
3. embed the `<!-- soleur:followthrough script=… earliest=… [secrets=…] -->`
   directive in the issue body (`earliest=` = the trigger date for a date form;
   the filing date for dependency/event-grep/counter forms, which self-gate via
   the probe's transient exit). **For any gh-using probe shape (dependency /
   event-grep / counter) the directive MUST declare `secrets=GH_TOKEN`** — the
   sweeper's `env -i` sandbox strips all but PATH/HOME + declared secrets, so a
   gh-probe without it is unauthenticated in CI and never closes (silent
   never-close). Only the date shape needs no `secrets=`.

Validation is NOT re-implemented here — the `gh issue create --label
follow-through` call is intercepted by
`.claude/hooks/follow-through-directive-gate.sh`, which fails-closed if the
directive is missing/malformed, the script path escapes the followthroughs
root, the script is absent/non-executable, or `earliest` doesn't parse. **Ordering:**
scaffold + `chmod +x` the script BEFORE the `gh issue create` call (the gate and
the sweeper both require the file on disk; for review-time filings it lands in
the review PR's branch). Full contract:
[`followthrough-convention.md`](../../../../knowledge-base/engineering/operations/runbooks/followthrough-convention.md)
§Trigger → verification mapping. This subsection is additive — the cost-of-filing
gate, the four scope-out criteria, and the CONCUR gate above are unchanged.

Everything else (magic numbers, duplicated helpers, small refactors, missing
tests for PR-introduced code, polish, naming, a11y on PR-introduced surfaces,
performance issues introduced by the PR) MUST be fixed inline.

**Bundle scope-outs by trigger.** Before filing, group candidates by trigger-equality (same date OR same counter threshold OR same `#N` dependency OR same human-review gate). File ONE issue per group with a sub-task checklist of the bundled items. CONCUR runs once per group, not per item. See `plugins/soleur/skills/review/references/review-todo-structure.md` §Bundling example.

The bundling check is operator-side because `code-simplicity-reviewer` only
sees one finding at a time and cannot recognize trigger-sharing across the
batch. Run the check on the synthesized candidate list before any CONCUR
invocation. If the operator misses a bundling opportunity and CONCUR is
invoked on items that obviously share a trigger, `code-simplicity-reviewer`
SHOULD DISSENT with `DISSENT: bundle with #<sibling-finding>` so the
operator collapses the filings.

**Second-reviewer confirmation gate:** Before creating a scope-out issue under
any criterion (including a bundled issue), invoke `code-simplicity-reviewer`
via Task. The prompt MUST include:

1. The finding (location, description).
2. The proposed fix.
3. The exact four scope-out criteria definitions from this section
   (cross-cutting-refactor ≥3 unrelated files, contested-design with
   independent agent-named tradeoffs, architectural-pivot, pre-existing-
   unrelated). Do not rely on the agent's prior knowledge of the criteria —
   pass the definitions literally.
4. The criterion being claimed and a 1-3-sentence rationale.
5. The proposed **re-evaluation trigger** in one of the four concrete trigger shapes (see plugins/soleur/skills/review/references/review-todo-structure.md §Re-evaluation Trigger). Human-review gates route through the dependency trigger shape (file a reminder issue assigned to the human, then dep-trigger on that issue).
6. This instruction: "Default to rejecting the scope-out filing. Only co-sign
   when the claimed criterion is concretely and obviously correct against the
   four definitions above AND the proposed re-evaluation trigger matches one
   of the four concrete forms (date / counter / event-grep / dependency).
   DISSENT on any vague re-eval trigger ('when it feels right', 'when we have
   more users', 'post-MVP', 'later', 'when this is a problem'). Reply with a
   single line as the first line of your output: `CONCUR` (to co-sign the
   filing) or `DISSENT: <one-sentence reason>` (to flip to fix-inline).
   Everything after the first line is advisory context."

**Concrete re-evaluation triggers.** Every scope-out filing's `Re-eval by:` field MUST take exactly one of four shapes: date / counter / event-grep / dependency (the last subsumes human-review gates via a reminder issue). The canonical definitions, examples, and rejected phrasings live in `plugins/soleur/skills/review/references/review-todo-structure.md` §Re-evaluation Trigger — `code-simplicity-reviewer` MUST DISSENT on any filing whose trigger does not match one of those four shapes.

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
       the `pre-existing-unrelated` criterion AND a concrete re-evaluation
       trigger in one of the four forms (date / counter / event-grep /
       dependency — see "Concrete re-evaluation triggers" below and
       [review-todo-structure.md](./references/review-todo-structure.md)). Vague phrasings ("post-MVP",
       "later", "when ready", bare phase labels with no linked
       phase-completion issue) are NOT permitted — they become the backlog
       this rule exists to drain.
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

- Is the fix ≤100 lines AND ≤4 files? → Remove from the scope-out list; fix
    inline and add to "Fixed inline" instead.
- Is the only objection bookkeeping ("feels like a follow-up", "not core to
    this PR") rather than a concrete technical contest? → Remove; fix inline.
- Did `code-simplicity-reviewer` actually CONCUR on this specific item (not
    just on the batch)? Required even in pipeline mode. → If no CONCUR, fix
    inline.

Only items that survive ALL three checks appear in "Filed as scope-out". This
loop prevents the failure mode where pipeline mode rationalizes filing
≤100-line cleanup items because the marker template makes filing look like a
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
   # --state open is deliberate (#6786): this previews ship's Phase 5.5 gate, which
   # blocks on OPEN review-origin issues only, so the states must match.
   gh issue list --label deferred-scope-out --state open --search "Ref #<PR_NUMBER>"
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
3. **Emit the review-evidence trailer (ALWAYS — not conditional on step 2)**, via
   [emit-review-trailer.sh](./scripts/emit-review-trailer.sh).

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/review/scripts/emit-review-trailer.sh" --findings <n>
   ```

   This is a script invocation rather than a described `git commit` line because
   the described form has measured zero compliance on exactly the branches that
   matter. Step 2 above tells you to skip the commit when there are no local
   changes — which is the *expected* case — so a review that finds nothing
   leaves no local evidence at all, and every downstream review-evidence gate
   then reads "review never ran" and denies the merge with no escape hatch
   (issue 6724).

   The script therefore commits `--allow-empty`. It is idempotent (a second
   review pass will not stack a duplicate), it refuses to run on `main`/`master`
   or in detached HEAD, and it verifies the trailer actually parses before
   reporting success — an unparseable trailer looks like evidence to a human
   reading the log while being invisible to the gate that consumes it.

   Run it even when step 2 committed something: the trailer is the durable
   machine-readable signal, and the commit subject is only a legacy fallback.
4. Display: "Review complete. All findings are tracked as GitHub issues.
   Run `/clear` then `/soleur:work` or `/soleur:ship` for maximum context headroom."

### 7. End-to-End Testing (Optional)

**Read `plugins/soleur/skills/review/references/review-e2e-testing.md` now** for project type detection, testing offers (Web/iOS/Hybrid), and subagent procedures for browser and Xcode testing.

### Defect Classes This Review Reliably Catches

Multi-agent parallel review has been shown to catch bugs in shipped, green-CI code across these classes (each a real P1 caught on PR #2347):

- **Shared mutable state across co-mounted instances** — module-level `let` bindings captured by a once-built object that multiple components import. Pattern-recognition and code-quality agents spot the closure capture in seconds; unit tests rarely co-mount instances.
- **Validator scope on sibling message fields** — new top-level fields added to a schema whose existing validator covers only one field. Security-sentinel asks "what if the client sends X?" for every permutation without waiting for the test author to imagine it.
- **DB partial-index predicate drift** — the application's query filter (`.is("archived_at", null)`) no longer matches the index's `WHERE` clause. Data-integrity-guardian reads both files and compares WHERE clauses symbolically; the bug stays silent until a user archives a row.
- **Feature-wiring composition bugs** — module A is correct in isolation, module B is correct in isolation, but A+B together violate a constraint that lives in module C (downstream consumer, scheduler, taxonomy). Examples: `leaderId: "system"` reusing an internal taxonomy value whose UI semantics collide with router output; a `registry.reap()` method with no scheduler outside tests (tsc is silent on "never called in prod"); a nullable callback parameter the caller contract forbids but the implementer maps to a value that breaks invariants. Review prompts must enumerate the downstream consumer / scheduler / invariant explicitly for agents to reach it. See `knowledge-base/project/learnings/best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`.
- **Runtime-content tamper between authoring and execution** — when a workflow fetches content (issue comment, file at remote URL, external service response) at fire/run time and acts on it, the gap between fetch-time integrity and execution-time mutability is a single-user incident-class vector. "No inline prompts" prevents leak-via-committed-YAML; it does NOT prevent attacker-edits-the-source-between-create-and-fire. `user-impact-reviewer`'s "name artifact + name vector" mandate reliably surfaces this where simplicity-biased peer review at plan time does not. PR #3067 added D5 (commenter-author-pin + immutability-pin) after the 11-agent review caught the gap that 3-reviewer plan-time review missed. See `knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`.
- **Cross-stream format-contract drift in telemetry joins** — when a feature joins two telemetry streams (a producer and a consumer that look up by name), test fixtures that use a simplified shared format on both sides hide bugs where the producers actually emit different shapes (namespaced `"plugin:name"` vs bare `"name"`, dotted IDs vs slashed IDs, hashed keys vs raw keys). Review agents and unit tests both miss this because each side's tests look internally consistent. The defect surfaces only via a derived-metric counter (orphan rate, miss rate, fall-through rate) whose surprising value points back at the contract. PR #3124 surfaced a `soleur:plan` (hook) vs `plan` (inventory) mismatch only after the orphan-skill counter — added as polish — reported a non-zero count in production data. See `knowledge-base/project/learnings/2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md`. Reviewer takeaway: when a PR adds a join across two streams, ask whether at least one fixture per side uses each producer's actual emission format, not a normalized placeholder.
- **Handshake schema drift between producer (skill) and consumer (file)** — when a skill instructs an operator to write a row/entry to a knowledge-base file, the producer's instruction template and the consumer's documented schema can drift in the same PR. Same column count + different semantics = silent table-corruption when followed verbatim. `data-integrity-guardian` catches this by reading both sides and comparing column-by-column. Reviewer takeaway: when a PR adds an instruction "write a row to file Y" alongside a schema documented in Y, grep Y's schema and assert the producer's row template matches column-by-column. Prefer reference-and-defer (instruction says "use the schema in Y") over embed-and-pray. PR #3501 shipped `gdpr-gate` with this exact drift; data-integrity-guardian flagged it as P1 pre-merge. See `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.
- **Replicated literals across ≥2 source files without parity test** — canonical regexes, schema strings, taxonomy IDs replicated across SKILL.md prose, hook scripts, test files, and config globs drift independently. Three reviewers in PR #3501 independently flagged a path-regex stored in 4 places. Reviewer takeaway: when a PR adds the same literal across ≥2 source files, expect a parity test (`expect(scriptContent.match(/^FOO='([^']+)'/)![1]).toBe(SOURCE_LITERAL)`). If absent, file as P2 inline-fix. Same learning file as above.
- **Self-claimed cross-artifact contract drift** — when a code/config file carries a comment, README line, or docstring claiming fidelity to another artifact (e.g., `globals.css: "Token names mirror brand-guide.md exactly"`, `schema.sql: "matches the TypeScript types in lib/types.ts"`), edits to either side can silently break the contract. Pattern-recognition, architecture, and code-quality reviewers approve the diff in isolation because each reads only the LOCAL file. Only an agent that reads BOTH files surfaces the contradiction. Reviewer takeaway: when the PR touches a file containing a "mirrors X" / "matches X" / "kept in sync with X" / "tracks X" self-claim comment, include in the review prompt: *"Read the named artifact X and verify the claim still holds post-diff."* Cheapest gate: `git diff origin/main...HEAD --name-only | xargs rg -l "(mirror|matches|kept in sync|tracks|reflects) (the )?(knowledge-base/|docs/|spec/)"` — every hit demands cross-artifact verification. PR #3556 (font normalization) shipped with the dashboard typography diverging from brand-guide.md; only git-history-analyzer caught it pre-merge. PR #3596 (Anthropic DPA row) confirmed an **implicit sub-pattern**: the grep above returns zero hits (no self-claim comment exists), but `compliance-posture.md`'s vendor-row framing still contradicted `docs/legal/gdpr-policy.md`'s public disclosure for the same vendor — only security-sentinel caught it. **Domain-specific gate:** for any diff under `knowledge-base/legal/`, the review prompt MUST instruct an agent to read `docs/legal/{gdpr,privacy}-policy.md` for the vendor name(s) in the diff and verify the diff's framing of vendor role / data flow / transfer mechanism agrees with the public disclosure. See `knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`.
- **Vendor-pipeline trust-contract gaps (auto-PR-of-untrusted-bytes / tautological integrity / exit-code-as-result)** — when a PR establishes a new vendored-content pipeline (pinned upstream blob SHAs + scheduled drift workflow + integrity gate + severity classifier), four trust-model classes compose badly across the pipeline's boundary contracts: (1) auto-PR routing across security-relevant drift classes converts a detection signal into a write primitive (compromised upstream → bot-authored PR → review fatigue); (2) self-consistency integrity check (working-tree hash + frontmatter SHA both PR-author-mutable) is tautological — ask "what other thing must move to bypass this?"; (3) classifier that emits ONE exit-code result silently under-labels co-occurring categories (e.g., security + license drift in one upstream commit); (4) inline-Python/awk parsers with non-greedy or fragile tokenization can no-op silently when YAML formatting drifts. `user-impact-reviewer` names the adversary model; `data-integrity-guardian` runs the regex against the real input and produces the falsifying case. PR #3521 shipped all four; multi-agent review caught them pre-merge. Reviewer takeaway: for PRs establishing trust contracts, require (a) integrity check has at least one cross-domain anchor (CI-side `gh api` upstream verification, signed-commit, CODEOWNERS), (b) classifier emits multi-category stdout AND exit code, (c) auto-PR routing restricted to lowest-risk class only, (d) post-condition assertions on regex/awk substitutions (`subn` count == expected). See `knowledge-base/project/learnings/2026-05-11-multi-agent-review-vendor-pipeline-trust-model.md`.
- **Single-literal gate over a multi-member union/enum** — when a TypeScript predicate gates behavior on `X === <literal>` (or `!isFoo`, `status === "completed"`) and `X` is a union/enum with ≥ 3 members, the gate is correct only by coincidence unless every union member has been classified include/exclude in the originating FR. `user-impact-reviewer` and `pattern-recognition-specialist` reliably catch this **only when the review-spawn prompt explicitly enumerates the union members** — without the prompt, agents echo the plan's single-value framing as a false-pass. Reviewer takeaway: the review-spawn prompt MUST enumerate the union members literally — without that, agents echo the plan's single-value framing as a false-pass. Concretely: when reviewing a gate conditioned on `X === <literal>` where `X` is a TypeScript union/enum, grep the type's declaration (`rg "type X =" <module>` or `grep -nE "X = .*\|"`) and pass the resulting member list verbatim into the spawn prompt, then ask "is the gate correct for each value?" Single-literal gates against multi-member unions are a known defect class. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; /work bound the gate to `streamState === "streaming"` while `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`). `"stopping"` is a distinct in-flight substate that mid-aborts traverse; a Stop click could have flashed the marker during that window. Caught only because the spawn prompt explicitly named the 3-value enum. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

- **Plan-time empirical-probe assumptions vs. actual caller surfaces** — when an ADR captures a plan-time probe that validated a discriminator field (e.g., "the hook event carries `authentication_method='otp'` ONLY on the runtime path"), the probe ran against ONE caller. The assumption may not hold for other callers in the codebase that hit the same upstream API differently (e.g., user-facing dashboard auth that ALSO triggers `authentication_method='otp'` via a different SDK shape). `security-sentinel` should grep the codebase for non-canonical caller patterns whenever the diff includes a SECURITY DEFINER function or auth-issuance hook that gates on a probe-validated field. Reviewer takeaway: when reviewing a PR that adds an auth-event-gated function, the spawn prompt MUST instruct security-sentinel to enumerate every caller-side surface that hits the same upstream API and confirm the gate's assumption holds for each. **Why:** PR #3983 — ADR-033 §0.4 pre-committed `authentication_method='otp'` as the runtime/dashboard discriminator (probe-validated for runtime); user-facing dashboard uses `signInWithOtp` which produces the same `authentication_method='otp'` → every dashboard JWT was being hook-rewritten with `aud=soleur-runtime`, `exp=600s` (10-min auto-logout). Marker-table pivot landed as migrations 049/050. See `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md`.

- **Parser-consumer invariant seam bypass** — multi-layer pipelines (`awk` emits per-token → `bash read` loop assigns last-wins; JSON-parser emits per-array-element → consumer overwrites by key; regex-extract → `Map.set` last-write-wins) where the parser-side enforced invariant (first-wins, deduplicated, unique-by-key) is silently violated at the consumer boundary. Plan-time review of the parser fix in isolation misses this because the bypass lives in the seam BETWEEN layers. Multi-agent review reliably catches it when the spawn prompt explicitly instructs *"trace the data flow from raw input through every transformation layer and assert the claimed invariant holds at every consumer boundary"*. Reviewer takeaway: when a PR's plan claims a parser-side invariant (e.g., "first directive wins," "deduplicated by key"), enumerate every consumer layer the parsed output crosses and require at least one test that injects N>1 matching tokens of the SAME key per record. PR #4200 — security-sentinel surfaced multi-`script=` last-wins WITHIN a single directive after the plan's Gap-2 fix closed multi-DIRECTIVE first-wins; the awk for-NF-loop emits one line per matching token and the bash `case "$key" in script) script=$val` was still last-wins. See `knowledge-base/project/learnings/2026-05-20-parser-emits-per-token-bash-read-loop-last-wins-within-directive.md`.

- **Legal-disclosure prose hallucinated against the actual migration body** — when a docs-only PR discloses a database substrate landed by a prior PR (legal docs, privacy policy, vendor DPAs, transparency reports), the disclosure prose is typically authored from the plan's conceptual narrative rather than from the migration body; the writer hallucinates plausible-sounding column names, RPC signatures, trigger bypass mechanisms, and DSAR allowlist semantics. The plan-time loop and per-AC grep gates do NOT catch this because none cross-grep the prose against the implementing files. Reviewer takeaway: when the diff touches `docs/legal/`, `plugins/soleur/docs/pages/legal/`, or `knowledge-base/legal/` AND cites an implementing PR/migration, the spawn prompt for `security-sentinel` AND `code-quality-analyst` MUST instruct: "Cross-check every implementation-detail claim in the new prose (column names, RPC signatures, trigger bypass mechanism, cascade step numbers, DSAR allowlist entry, ON DELETE behavior) against the migration body, the RPC body, and the consuming TypeScript file; produce a column-by-column drift table." **Why:** PR #4353 — two independent agents (security-sentinel + code-quality-analyst) caught 4+ fabricated identifiers (`organization_id`, `user_id` vs actual `removed_user_id`, `removed_user_email_hash`, `removal_reason`, `SET LOCAL session_replication_role`) that the plan's deepen-pass + 11 AC grep gates all missed. See `knowledge-base/project/learnings/2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md`.

- **Stale plan-time RLS-policy enumeration drift** — when a PR sweeps RLS policies across "all" tenant tables based on a plan-time grep, the table list decays as sibling PRs land between plan-write and PR-merge. Multi-agent review reliably catches this when the spawn prompt for `data-integrity-guardian` AND `security-sentinel` instructs: "Re-derive the canonical authenticated-policied table list at review time via `grep -rnE 'POLICY.*ON public\.[a-z_]+ .*TO authenticated' apps/web-platform/supabase/migrations/*.sql` and assert every match has the new RESTRICTIVE policy." PR #4418 — both agents independently caught 2 missed tables (`organizations`, `workspace_member_removals`) the plan's enumerated "19 tables" list missed; verify sentinel widened to per-table intersection. See `knowledge-base/project/learnings/2026-05-25-multi-agent-review-catches-stale-precedent-grep-and-unreachable-ux-toast.md`.

- **RLS-policy-expression edit breaks exact-string verify/ sentinels AND aborts on dev/prod policy divergence** — when a migration edits an RLS policy's DEPARSED expression (an `auth_rls_initplan` wrap `auth.uid()` → `(select auth.uid())`, a predicate rewrite, a role/qual edit), it has two blast radii beyond the policy itself that pass tsc + the vitest suite + migration-shape lints and only fail POST-MERGE (verify-migrations against prod, tenant-integration against dev). The spawn prompt for `data-integrity-guardian` AND `security-sentinel` MUST instruct: (a) `git grep -l "<policyname>" apps/web-platform/supabase/verify/` for every touched policy name and update each stale exact-string sentinel (`ILIKE '%...auth.uid()%'`) in the SAME PR — or make it wrap-tolerant (`~* 'user_id = \(? *(select +)?auth\.uid\(\)'`, preserving the anti-false-green prefix), verified against live prod `bad=0`; and (b) require each `ALTER POLICY` to be guarded by a `pg_policies` existence check (`DO $do$ BEGIN IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=... AND policyname=...) THEN ALTER POLICY ...; END IF; END $do$;`) because `ALTER POLICY` has no `IF EXISTS` and a policy name sourced from ONE project's live catalog is not guaranteed present on the other (`hr-dev-prd-distinct-supabase-projects`) — a single absent policy aborts the whole migration. **Why:** PR #6663 — an initplan wrap (migration 134) broke `verify/129`'s exact string-match (hotfix #6671) and aborted the dev apply on `conversations_owner_delete` (absent on dev). See `knowledge-base/project/learnings/2026-07-18-rls-initplan-wrap-breaks-verify-sentinels-and-dev-prod-policy-divergence.md`.

- **Closed privacy-field-list classified at column-NAME instead of column-VALUE-SHAPE** — when a PR introduces a closed denylist of "fields to null on rows belonging to a third party" (Art. 15(4) author redaction, DSAR allowlist, log scrub field set, response-redaction filter), plan-time review reliably approves the list at column-name level ("`tier` is an enum, looks structural") without cracking open the migration COMMENT body to read the actual value shape. The asymmetry is dangerous: one too many preserved column = single-user privacy leak (brand-survival); one too many redacted column = a structural-shell row the subject can still see. Two ORTHOGONAL post-implementation agents (one reading migration COMMENTs for namespace patterns, one reading COLUMN TYPES + ROPA prose) reliably catch this where plan-time review misses it. Reviewer takeaway: when reviewing a PR that defines a closed field-list over a database table, the spawn prompt for `security-sentinel` AND `data-integrity-guardian` MUST instruct: "For each column NOT in the redact list, read the migration ADD COLUMN line AND its COMMENT body. Classify as (a) free-text → REDACT, (b) namespace-identifier shape `<prefix>-<org>:<value>` or email-shaped → REDACT, (c) signal-about-third-party (even closed enum like `tier='external_brand_critical'`) → REDACT, (d) UUID/integer/timestamp/known-bounded numeric → preserve. Produce a column-by-column classification table." Also require a CI sentinel test that parses migrations for `ALTER TABLE <table> ADD COLUMN` and asserts every observed column is classified in REDACT or ALLOWLIST. **Why:** PR #4351 — security-sentinel + data-integrity-guardian independently flagged that `source_ref` / `owning_domain` / `urgency` / `leader_id` / `template_id` / `tier` / `source` / `trust_tier` (8 columns the plan classified as "structural preserve") carry free-text business semantics that leak third-party content; user-impact-reviewer silently approved the original 5-field list at column-name level. Sentinel test added at `apps/web-platform/test/dsar-message-redact-fields-sweep.test.ts`. See `knowledge-base/project/learnings/2026-05-25-closed-field-list-must-classify-at-value-shape-not-column-name.md`.

- **Temporal-qualifier gap on sequenced legal-then-code rollouts** — when PR-1 of a multi-PR sequence lands disclosure prose for behavior that PR-N+1 will implement (the "land legal before code" Art. 13(1)(e) prior-disclosure pattern), present-tense disclosure claims ("`transient: true` MANDATORY", "data egresses to vendor X") misrepresent the current code state. Plan-time review optimizes for "is the disclosure accurate post-PR-N+1?" (yes) and misses "is the disclosure accurate at PR-1 merge?" (no). Multi-agent review at PR-1 time reliably catches this only when the spawn prompt for `legal-compliance-auditor` AND `security-sentinel` instructs: "For each forward-looking claim in the new disclosure (verbs like `MANDATORY`, `MUST pass`, `always`, `every call`, `egresses`), identify the PR that lands the code-side enforcement, then grep the current codebase to confirm the claim is or is not live. Each claim must be either backed by current code OR qualified with a temporal marker ('effective on PR-N merge', 'will pass', 'once PR-N merges')." Article 13(3) prior-disclosure is the legal precedent. **Why:** PR #4455 (umbrella #4456 PR-1) — Flagsmith sub-processor disclosure landed asserting `transient: true` MANDATORY + `orgId` egress as present-state facts; actual code at `apps/web-platform/lib/feature-flags/server.ts:86` called `getIdentityFlags(\`role:${role}\`, { role })` (PR-2 lands those). 3 agents independently surfaced; fixed with Art. 13(3) qualifiers + explicit "Current code-side state at PR-1 merge" subsection. See `knowledge-base/project/learnings/2026-05-25-pr1-of-sequenced-legal-disclosures-needs-temporal-qualifiers.md`.

- **Emit path re-pointed to a different alert primitive drops a tag the destination rule filters on** — when a PR re-routes an observability emit (e.g. `reportSilentFallback` → `mirrorP0Deduped`) to a primitive feeding a `filter_match = "all"` Sentry rule, the new primitive may not emit every `tagged_event` the rule ANDs on. The old primitive often supplied a *scoping* tag (`feature=...`) implicitly via a required option; the plan names only the *distinguishing* tag (`art_33_breach`) and the scoping tag silently drops → the rule never matches → a real breach never pages. tsc and a single-tag test both pass. Reviewer takeaway: when a PR re-points an emit at a different alert-feeding primitive, the spawn prompt for `security-sentinel` MUST instruct: "read the destination rule's `filters_v2`, enumerate every `tagged_event` key under `filter_match='all'`, and confirm the new primitive emits each one." **Why:** PR #4658 (#4656) — `mirrorP0Deduped` emitted `art_33_breach` but not `feature=byok-delegations`; caught at plan-gap time and confirmed by review. See `knowledge-base/project/learnings/best-practices/2026-05-30-routing-through-shared-tag-filtered-alert-primitive-needs-all-filter-tags.md`.

- **An alert whose filter tag is DERIVED from the same predicate that gates the alerted action is a DEAD tripwire — it can never fire** (the tautology sibling of the missing-tag bullet above). When a PR adds a Sentry/monitor alert on a fail-safe action (an auto-close, an auto-refund, a fail-closed abort) filtering on `<tag>=<value>`, and the emitting code sets `<tag>` from the SAME boolean that gates the action, the tag is tautologically fixed at the non-alerting value on every real firing — the "we did the dangerous thing anyway" backstop is structurally inert while reading as protection. Reviewer takeaway: for any alert on a guarded action, ask "can the filtered tag EVER be `<value>` when the action fires under CORRECT code?" If no, the fix is to compute the tag via an INDEPENDENT re-derivation at the action site (a fresh re-check decoupled from the decision), so a disagreement between "the action fired" and "the invariant says it shouldn't have" is what trips it (also often closing a TOCTOU window). Companion, same class: two surfaces that de-pollute/gate on a label set — a READ surface (render/digest/filter) and a WRITE surface (classifier/close-authority) — MUST key on the SAME predicate; a divergence where the read hides what the write keeps silently drops the exact edge case one was designed to preserve. **Why:** #6836 — the veto-bypass alert's `human_engaged` tag came from `decision.humanEngaged`, which `decideAction` only emits `false` on expire, so the alert could never fire; and the digest §4 excluded broad `content` while the cron classified it OPS, dropping a live escalated emergency from the operator's only surface. See `knowledge-base/project/learnings/2026-07-22-review-catches-a-dead-tripwire-and-a-cross-surface-predicate-divergence.md`.

- **Multi-step saga fix that addresses only the reported failing step / the symptom-named failure mechanism** — when a bug report names ONE failing step of an abort-on-first-error saga (account-delete cascade, multi-RPC pipeline, ordered migration chain), the reported symptom is a LOWER BOUND on the blast radius, not the blast radius: the saga only ever surfaces the FIRST broken step, and downstream steps can be broken by a DIFFERENT mechanism the symptom-grep misses. `architecture-strategist` (prompted to compare the fix against codebase precedent) and `data-integrity-guardian` reliably catch this where the plan + symptom-grep + operator framing do not. Reviewer takeaway: when a PR fixes one step of a saga by swapping a shared mechanism (a WORM-bypass, an auth gate, a serialization format), the spawn prompt MUST instruct an agent to (a) enumerate EVERY mechanism that can break the same operation class — not just the one the symptom names — via a live-DB / full-codebase scan (e.g. `pg_get_functiondef ILIKE '%session_replication_role%' OR ILIKE '%current_user%service_role%'`), and (b) confirm each remaining saga step is healthy by reproducing it on a REAL row (a 0-row call is vacuous — row-level triggers never fire). **Why:** PR for #4696 — the `session_replication_role` (42501) fix addressed 7 saga functions; review surfaced that `anonymise_tc_acceptances`/`anonymise_dsar_export_audit_pii` (mig 041/044) carry a SECOND, independent broken bypass (the proven-dead `current_user='service_role'` gate → always P0001), empirically reproduced on a real `tc_acceptances` row; without the catch, erasure stayed broken end-to-end at a later step. See `knowledge-base/project/learnings/2026-05-31-worm-bypass-fix-must-enumerate-all-mechanisms-not-just-the-reported-one.md`.

- **Plan-asserted "structurally prevented" safety invariant landed as prose-only guard** — when a plan's Domain Review / User-Brand Impact claims a dangerous branch is "structurally prevented" / "never auto-X", `/work` can encode the guard on a *proxy* (`status != "resolved"`) instead of the *actual determining signal* (`lastSeen < deploy timestamp`), so the bad branch stays reachable and the prevention lives only in surrounding prose. Reviewer takeaway: when the diff adds a state-mutating action gated on a safety claim, the spawn prompt MUST name the invariant and ask "is the determining signal bound to a variable and present in the `if`, or only in the interpretation prose?" Require the guard to compute one mechanical boolean (fail-safe-false on ambiguous data), not a human-read interpretation step. **Why:** PR #4681 — postmerge auto-resolve PUT guard checked only `status != "resolved"`, omitting the `lastSeen`/deploy comparison; would have false-resolved a still-firing issue (hiding a live error). All 4 review agents independently caught it. See `knowledge-base/project/learnings/best-practices/2026-05-31-plan-asserted-structural-guard-must-be-encoded-not-prose.md`.

- **"Exactly one X per state" invariant that spans a composition boundary** — when two components on opposite sides of a layout/route-swap boundary each own one instance of the same affordance (back button, page title, primary CTA, identity chip), a component-scoped render test can only assert "X is present/absent in MY subtree" and is structurally blind to the sibling. The duplication (or zero-case) ships green because each test is internally consistent. `user-impact-reviewer` (tracing the state-by-state table across the full composition) reliably catches it where the unit suite cannot. Reviewer takeaway: when a PR adds chrome (back/title/CTA) in a page-level component that a persistent parent ALSO renders, require (a) both consumers keyed on ONE shared predicate so mutual exclusivity is by-construction, and (b) a **count** assertion at the composition root / e2e real-viewport (`getByRole(...).toHaveCount(1)`), never a per-component `getByX` presence check. Smell: a subtree-scoped test titled "…it is the only X there" — "only" is a document-level claim a subtree test cannot back. **Why:** PR #4911 (#4915) — a Phase-4 KB page-header "Back to menu" duplicated the persistent band's back on the mobile KB landing; the band-scoped unit test asserted a false "only back there" premise and the e2e asserted existence without a count. Fixed by keying band `suppressBack` + page-header `showHeaderBack` on a shared `isKbDocView(pathname)`. See `knowledge-base/project/learnings/ui-bugs/2026-06-04-exactly-one-affordance-across-composition-boundary-needs-integration-count-assertion.md`.

- **Credential/PII redaction fix that scrubs only the NEW path and misses the pre-existing sink that actually leaked** — when a PR exists to fix an observed leak (a token in a screenshot) and the plan even cites the exact `file:line` origin, `/work` frequently adds redaction on the new feature path and leaves the cited legacy sink untouched; tsc + the new path's own redaction tests pass green, so the gap is invisible to every implementation-side check. `user-impact-reviewer` (fired by a `single-user incident` threshold) catches it by enumerating leak vectors per user-role and noticing the diff never touched the cited origin. Reviewer takeaway: for any leak/redaction PR, the spawn prompt MUST instruct the security/user-impact agent to `git grep` EVERY sink that renders the offending value (wire send, push/offline notification, persisted row) — explicitly including pre-existing paths the diff does not touch — and confirm each is gated; if the plan cites a `file:line` leak origin, require an AC that greps that exact site for the redactor call. The render-time analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`. **Why:** the concierge command-stream PR — implementation redacted only the new `command_stream` path; the default-posture `review_gate` question at `permission-callback.ts:459` (the literal screenshot leak) shipped raw until review. See `knowledge-base/project/learnings/security-issues/2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path.md`.

- **A new consent/approval gate that reuses a shared resolver registry keyed only by id (no type discriminator) is bypassable by the sibling gate's response frame** — when a hold/resolve primitive (review-gate, approval queue, payment-capture hold) is reused for a NEW gate type that carries a type-specific side effect (a consent/ack write, an audit row, a capture), and held entries share one registry keyed only by `gateId`, a response frame for gate type A can resolve a held gate of type B and release it WITHOUT performing B's side effect. The auth on the side-effect RPC does not protect you — the attacker releases the command through the *other* frame, never calling the RPC. tsc + same-frame unit tests (which mock the hold primitive and never drive the cross-frame release) pass green; only `security-sentinel` driving the cross-frame path catches it. Reviewer takeaway: for any new gate sharing a resolver registry, the spawn prompt MUST instruct the agent to enumerate EVERY response frame that can resolve the shared registry and confirm each cannot release a gate whose side effect it doesn't perform; require a test driving the cross-frame path. Fix = tag gates by kind + reject cross-kind resolution AND re-assert the side-effect invariant (re-read the consent row) at the enforcement boundary before `allow()`, not just trust the frame type. Adjacent reflex: a `Date.parse`/`Number()` coercion feeding a fail-closed `== null` gate fails OPEN on `NaN` (`NaN == null` is false) — guard with `Number.isFinite`. **Why:** the autonomous-consent soft-gate PR — a `review_gate_response` released a held `autonomous_disclosure` gate without the owner-checked ack write (consent bypass); the ack-timestamp `Date.parse` NaN was read as "acked". See `knowledge-base/project/learnings/security-issues/2026-06-04-consent-gate-sharing-untagged-resolver-registry-is-bypassable.md`.

- **Telemetry-blind fatal give-up on a headless/sandbox surface (invisible to the marker pipeline)** — when a PR adds or changes a failure emit on a non-inspectable execution surface (agent sandbox, container readiness gate, cron worker), the fatal path can route through a logfile sink (`headless_or_stderr` → per-PID logfile, not scanned stdout) AND/OR carry a `[<level>] ` prefix that fails the destination `MARKER_RE` anchor — so the give-up fires on every failed run yet the dashboard shows ZERO events, and "zero events" gets misread as exoneration. Four consecutive worktree-wedge fixes flew blind against a zero-events Better Stack query for exactly this reason. Reviewer takeaway: when a PR adds/changes a failure emit on a headless/sandbox surface, confirm the fatal path reaches a MONITORED **stdout** sentinel (not just a logfile) and that the destination marker regex tolerates any level prefix + allowlists the new sentinel; treat "zero telemetry events" that contradicts a direct operator observation as a coverage gap to verify, never proof the bug is absent. `observability-coverage-reviewer` owns the layer-citation check. See `knowledge-base/project/learnings/2026-07-07-telemetry-blind-giveup-and-mask-degraded-nonbare-guard.md`.

- **Source-text classification/containment gate that fails OPEN on a lexing or surface gap** — when a PR adds a static-source scan that gates behavior on detecting a pattern (a containment classifier over `cron-*.ts`, a "no raw SQL" linter, an import-allowlist), the GREEN suite proves only that *today's* tree classifies as expected — it cannot prove the detector fails CLOSED on a future input. Three fail-open classes recur, caught by `pattern-recognition-specialist` + `security-sentinel` (not by the passing suite): (1) **proxy-not-behavior** — detecting "imports module X" instead of "calls X's dangerous entrypoint" (a file can import a helper and still take the bad path); (2) **regex-not-lexer** — a comment/string stripper built from a `/* … */`-style regex bridges across string literals (a close-comment token inside a `"0 (slash)4 * * *"` cron string terminates a comment that a `/*` in a `//` comment opened, swallowing real code); (3) **partial egress surface** — `spawn(`-only detection that misses `execFile`/`execSync`/dynamic `child_process` import. Reviewer takeaway: when the diff adds a source-scan gate, the spawn prompt MUST instruct an agent to (a) enumerate evasion inputs the scanner would misclassify and state fail-open-vs-closed for each, and (b) require an adversarial-strip RED row + a non-degenerate-distribution guard, mirroring `function-registry-count.test.ts`. **Why:** PR #5203 (#5072) — the plan's import-regex + `spawn(`-only design would have RED-failed the clean tree AND shipped two fail-open holes; fixed with call-site detection + a stateful char-scanner lexer (two scan surfaces: strings-blanked for call tokens, strings-kept for module specifiers). See `knowledge-base/project/learnings/best-practices/2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing.md`.

- **A new "for-all-members" drift guard turns `main` RED when a concurrent sibling PR adds a member to the guarded set** — when a PR adds a test asserting a property over EVERY member of a set on a high-churn surface (every assertion in a terraform inline block carries a sentinel, every migration column is classified, every route is registered), a sibling PR that ADDS a member to that set on `main` is a non-conflicting *addition* git merges silently — so the new member fails the guard on `main` post-merge, never on the green PR branch. `code-quality-analyst` (prompted to re-derive the diff against fresh `origin/main`) reliably catches it where the branch's own green run cannot. Reviewer takeaway: when a PR introduces or tightens an all-members invariant, the spawn prompt MUST instruct an agent to `git fetch origin main` and check whether `main` has added un-instrumented members to the guarded set since the branch base; the fix is rebase-before-ship + instrument the new members. **Why:** PR #5280 (#5279) — an "every assertion carries an `ASSERT-FAILED` sentinel" guard would have turned `main` red after siblings #5281/#5285 added a bare CIDR assertion + an `enable`→`restart` split to the same block. See `knowledge-base/project/learnings/best-practices/2026-06-14-all-members-drift-guard-must-rebase-before-ship.md`.

- **A reused multi-step pattern faithfully copies the happy path but drops the precedent's failure-arm observability** — when a PR reuses a named precedent's two-phase commit / saga / optimistic-lock-then-write (often with a `// mirrors X` comment), the copy reliably reproduces the success path and sheds the precedent's Sentry/log mirror on the catch/error arms — the part that is invisible to a happy-path test and to `tsc`. Multiple agents converge on it ONLY when the spawn prompt names the precedent: instruct an agent to grep the cited precedent for `reportSilentFallback`/`Sentry`/`logger` calls on its failure arms and confirm each survived the copy, and require a failure-arm test (force the throw, assert the mirror fired), not a call-happened count. Companion class: when the PR reuses an existing code/enum STRING on a NEW transport channel (HTTP 409 reusing a WS-frame code), single-sourcing the literal does NOT stop the companion payload fields (id field name, key name) from drifting across channels — diff the two channels' payload shapes. **Why:** PR #5671 (#5673) — `handleSwitch` claimed to mirror `org-switcher-container.tsx`'s two-phase commit but its `refreshSession()` catch was empty, dropping the precedent's `op:refresh-session-post-rpc` mirror; code-quality + user-impact + data-integrity independently converged via the "mirrors X" comment. See `knowledge-base/project/learnings/best-practices/2026-06-29-reused-two-phase-commit-pattern-drops-precedent-observability.md`.

- **A path-filtered workflow promoted to a REQUIRED check whose change-detection anchors are narrower than the surface the suite verifies** — when a PR makes a path-filtered suite required (via an always-run aggregator gate job), a GREEN result becomes an *authoritative certification*, not a silent skip; an anchor set narrower than the verified surface produces a false-authoritative-GREEN (fail-open) that is strictly WORSE than the prior not-required state. The trap: anchors are inherited verbatim from the old `on.paths`, and reviewers verify "anchors faithfully reproduce the former `on.paths`" — the WRONG baseline. The `single-user-incident`-gated `user-impact-reviewer` catches it only when the spawn prompt instructs: "trace the suite's imports/surface and confirm every isolation-relevant file is an anchor; list each deliberately-unanchored path with a one-sentence justification." Reviewer takeaway: for any PR promoting a path-filtered check to required, the anchor set is a security contract — audit it against the verified surface (`grep` the suite's `import`s), not against the inherited filter, and require each accepted gap (e.g. all-routes anchoring that would defeat the rate budget) to be documented. **Why:** PR #5688 (#5585) — `tenant-integration` was made required with anchors covering only `server/`/`migrations/`, but 20/22 isolation tests import `@/lib/supabase/tenant` and exercise the RLS-bypass service-role client; user-impact-reviewer's P1 (empirically verified) widened anchors to the surface before merge. See `knowledge-base/project/learnings/2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`.

- **DB write-amplification / Disk-IO-budget regression** — our DB lenses check query CORRECTNESS (data-integrity-guardian) and read LATENCY (performance-oracle: N+1, index usage), but never write *frequency × per-write WAL cost*, so a write that is correct AND fast can still dominate the prod Disk-IO budget (the dominant Supabase cost lever). When a diff adds or modifies a `.insert()/.update()/.delete()` (supabase-js) call OR a migration on a per-request / per-webhook-delivery / per-cron-tick path, the review-spawn prompt for `performance-oracle` MUST instruct it to estimate calls/day (write frequency × the path's trigger) and assess WAL bytes, full-page-writes (FPI), autovacuum + index-maintenance churn, and retention — flagging per-delivery dedup / audit / log / heartbeat inserts especially, because retention bounds row-COUNT but NOT WAL (WAL is emitted per-write, so a dedup row that is deleted 5 minutes later still cost its full WAL + FPI). Reviewer takeaway: when a PR adds a write on a hot path, the spawn prompt MUST name the trigger and ask "how many of these per day, and what is each one's WAL cost?" — a bounded table is not a bounded WAL footprint. **Why:** PR #5736 — a webhook dedup `INSERT` into `processed_github_events` was **63% of prod WAL** (`pg_stat_statements.wal_bytes`, the dominant Disk-IO consumer) yet shipped through review + green CI because every lens checked correctness or read latency and none checked write frequency × per-write WAL; the fix dropped the no-side-effect deliveries before the dedup write. The continuous backstop is the `cron-supabase-disk-io` monitor's `op=wal-concentration` Sentry alert (top-WAL-statement detector).

- **User-facing downtime introduced without a zero-downtime path** — a change that takes a serving surface offline during the change itself (a host reboot/replace, a singleton→cluster cutover, a lock-taking/table-rewriting migration on a hot table, a single-host container swap without drain) ships as "a brief maintenance window" when a zero-downtime path existed and was never evaluated. None of the correctness/perf/security lenses flag it — the code is *correct*, it just costs an outage. When the diff touches `apps/*/infra/**` with a reboot/replace-class change, a migration with `ALTER TABLE`/non-`CONCURRENTLY` index/`ADD CONSTRAINT`-without-`NOT VALID` on a live table, or a deploy/router restructure, the review-spawn prompt for `architecture-strategist` (and `user-impact-reviewer` when the plan threshold is `single-user incident`) MUST instruct: "identify the offline-inducing operation, and confirm the plan's `## Downtime & Cutover` section evaluated a zero-downtime path (blue-green / expand-contract / `CREATE INDEX CONCURRENTLY` / `state mv` / drain-first) and defaulted to it — a bare maintenance-window acceptance without that evaluation is a finding." Reviewer takeaway: for availability-affecting changes, "it works" is not the bar — "it works AND stays up for users during the change, or downtime is explicitly justified + bounded + operator-signed-off" is. **Why:** #5887 — a `moved`-block migration was defaulted to a rebooting `terraform apply`; the wedge actually cleared with a zero-downtime `terraform state mv` and the real cutover is blue-green (fresh host born in the placement group, drain the old, reboot it last). This lens is the review-side of deepen-plan Phase 4.55.

- **Parity/classification-guard blind spots + extracted-then-specialized shared scripts** — three infra-review catches that co-occur when a PR adds a copy of a replicated literal, a terraform-plan classification gate, and a "shared" script. (a) A drift-parity guard that extracts the FIRST occurrence (`head -1` / `[0]` / `grep -m1`) is a *first-member* guard, not an all-members guard — a copy the SAME PR adds escapes it silently; require per-copy iteration + a known-copy-count assertion. (b) A gate that classifies terraform plan actions on `create/update/delete` has a `["forget"]` fail-open (`removed{}` state-drop evades it) — enumerate the FULL action vocabulary and RED-test the added verb. (c) A script "extracted for reuse" but specialized to its FIRST consumer (context-specific recovery strings, collapsed step structure, new guards) is NOT a clean swap for the sibling it was extracted from — migrating the origin is a structural refactor, so a CONCUR/simplicity gate assessing migrate-inline-vs-defer on a "small swap" premise can misjudge; verify the structural + messaging divergence, and when the DISSENT is on the criterion LABEL, re-file under the fitting criterion with that evidence. **Why:** PR #6030 — `head -1` un-guarded the new `WEB_HOST_PRIVATE_IPS` copy; the destroy-guard missed `["forget"]`; the shared verify script was recreate-specialized so the warm_standby migration deferred (#6040, contested-design). See `knowledge-base/project/learnings/best-practices/2026-07-05-extracted-specialized-shared-script-not-clean-swap-and-parity-blind-spots.md`.

- **Drift-guard/audit PR whose canonical mirrors an imperative SSOT, with a "first run green" AC** — when a PR ships an audit that compares a LIVE resource (GitHub ruleset, DNS/WAF config, vendor setting) against a canonical snapshot that mirrors a `create-*.sh`/`.tf`/config SSOT, the plan's post-merge "first cron run completes green, no false-positive" AC *pre-supposes live == SSOT* — the exact question the guard exists to answer. The SSOT and live can already be diverged (a required check added to the SSOT but never reconciled onto live). All the file-vs-file gates stay internally green while the first real run files a TRUE-POSITIVE. `code-quality-analyst` + a review-time `gh api`/`curl` **live probe** of the audited resource catch it (`hr-no-dashboard-eyeball-pull-data-yourself`). Reviewer takeaway: for any audit/drift-guard PR, live-probe the exact resource the audit compares against at review time; keep the canonical tracking the SSOT/desired state (never mutate it to match drifted live), surface the divergence as a decision-challenge + corrected AC, and do NOT silently reconcile production as a PR side effect. **Why:** PR #6070 (#6061) — the live CLA ruleset was missing `cla-evidence` (added to the SSOT by #3201, never applied to live); the audit's first run correctly flags it. See `knowledge-base/project/learnings/best-practices/2026-07-05-drift-guard-first-run-live-probe-the-audited-resource.md`.

- **A static-source CI drift-guard keyed on a `lifecycle { ignore_changes = [X] }`-decoupled attribute is blind exactly when X drifts** — when a PR adds a guard that parses Terraform `.tf` source and gates behavior on an attribute's declared value (a heartbeat's `paused`, a resource's `enabled`/`count`, a tag), `security-sentinel` + `pattern-recognition-specialist` reliably catch that the source value is only a LOWER BOUND on live state if the resource carries `lifecycle { ignore_changes = [X] }` — the operator mutates X out-of-band (a Better Stack UI unpause, a console toggle) and Terraform never reconciles it, so source reads the stale declared value forever. The guard then fails OPEN in the precise case it exists to catch. Reviewer takeaway: for any static-source drift-guard, `grep` the guarded resource for `ignore_changes` and confirm the guard depends on NO listed attribute; if it does, re-key the requirement on a structural, non-ignorable property (the resource CLASS / arming mechanism / a ForceNew attribute) and add a fixture proving the previously-exempt (declared-off) case now fails. **Why:** PR #6251 (#6242) — the heartbeat reprovision-parity guard keyed the path requirement on source `paused`, but 4/6 heartbeats ship `paused=true` + `ignore_changes=[paused]` + UI-unpause; two agents converged, fix re-keyed on the `dedicated-host-boot` arming class (paused-independent). See `knowledge-base/project/learnings/best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md`.

- **A multi-step publish made non-blocking collapses non-equivalent failure modes into one "degraded" bucket** — when a PR makes a copy-then-sign / upload-then-checksum / write-then-index publish non-blocking (`continue-on-error` + exit-0), the step's failure modes are NOT equivalent against the DOWNSTREAM consumer's fallback contract, and a single `degraded()`/catch handler hides it. A pull-side/read-side fallback that keys on **absence** (miss → use the other source) is silently defeated by a **present-but-invalid** artifact (present → used → fails a later integrity gate with no fallback left). The dangerous step runs *after* the artifact becomes visible but *before* it becomes valid (the sign after the copy). `security-sentinel` catches it ONLY when the spawn prompt names the downstream consumer and instructs it to trace each failure mode through that consumer's fallback logic; a correctness/pattern lens verifies the shell is internally correct and misses it (the defect is in the seam, another file). Also verify the remediation string actually clears the SPECIFIC fault (a bare `crane copy` backfill does not re-sign). **Why:** #6274 — the exit-0 zot mirror treated a `cosign sign` failure as a clean miss; a present-but-unsigned zot copy defeats the host's atomic GHCR fallback (`ci-deploy.sh` pulls the present copy, then hard-blocks on verify) post-cutover. See `knowledge-base/project/learnings/best-practices/2026-07-09-nonblocking-copy-then-sign-publish-sign-failure-is-not-a-clean-miss.md`.

- **A newly-sanitized structured marker/log added alongside a PRE-EXISTING raw diagnostic emitter on the SAME off-box sink leaks — and a prefix-scoped purity test passes green while it does** — when a PR adds a scrubbed/enum-mapped marker (`logger -t <tag>`, a redacted Sentry field) next to sibling diagnostic lines on the same journald tag / stdout / Sentry scope that still emit raw upstream error text (`errors[].message`, a stack frame), the sanitizer covers only the new emitter; a credential (`postgres://<user>:<pass>@<host>`) in the raw sibling ships to the third-party log store on the failure path. The purity test typically scopes its assertion to the NEW marker's prefix (`grep 'SOLEUR_' | grep -c '://'`), filtering OUT the leaking sibling → vacuous green. Two orthogonal agents converge (security-sentinel names the lines; user-impact-reviewer escalates when the plan's threshold is `single-user incident`). Reviewer takeaway: when a PR adds a sanitized emitter, `git grep` EVERY emitter to that sink (`logger -t "$TAG"`, the Sentry scope, the stdout body) and confirm each scrubs; require the purity assertion to run against the FULL sink capture, not the new prefix (the log-sink analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`). Corollary: a credential-leak assertion must target the credential shape (`user:pass@host:port`), not bare `://` — scripts legitimately print credential-less internal endpoint URLs. **Why:** PR #6283 (#6258) — the inngest pre-flight markers enum-mapped GraphQL errors but the sibling FATAL/ERROR `logger`/`echo` lines shipped a `postgres://` DSN verbatim; the SOLEUR-scoped purity test passed green. See `knowledge-base/project/learnings/security-issues/2026-07-09-sanitized-marker-alongside-raw-sibling-diagnostic-leaks-and-purity-test-scope.md`.

- **A new CI gate whose tests mirror the workflow in hand-written code pins the gate's INPUT, not the gate — and its probe can certify silence.** When a PR adds a guard (a jq counter + a workflow HALT) plus a follow-through probe, four failure shapes recur and all read green: (a) the counter's selector is narrowed by a **double-count argument that does not apply** — if the new key is not a term in the sum it claims to avoid double-counting against, the exactness only narrows the gate (a `-replace` births a host that `== ["create"]` misses), and it composes with the sibling gate that *tells* the author to `[ack-destroy]` past it; (b) the tests re-implement the workflow's bash, so **deleting the entire HALT leaves them green** — pin the gate's control flow against literal bytes (present + positioned above the ack-consulting sum + in the fail-closed numeric validation) or run the real block via `extract_run_block`; (c) a helper that structurally cannot read the ack "proves" ack-independence **tautologically**; (d) the probe reads a step `conclusion` masked by `continue-on-error`, greps a phrase that also appears in GitHub's **echoed run-block SOURCE**, matches `Post <step name>` with an unanchored matcher, or lets a missing producer fall through to PASS. Reviewer takeaway: for any guard PR, the spawn prompt MUST instruct an agent to **mutate the gate out of the workflow and re-run the suite** (green = the tests pin nothing), enumerate the FULL action vocabulary per shape (`["create"]` / `["delete","create"]` / `["create","delete"]` / `["forget"]`) naming which gate catches it and whether that gate is ack-bypassable, and require the probe to carry a **positive liveness marker** (producer-absence ⇒ TRANSIENT, never clean). **Why:** PR #6421 (#6416) — all four shipped; `security-sentinel` found the replace fail-open, `test-design-reviewer` proved the HALT deletable with 33/33 green, `observability-coverage-reviewer` found the probe PASSing on the mirror step's absence. See `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`.

- **A drift-guard that block-scopes source with `indexOf`/`slice` swallows SIBLING blocks into a vacuous GREEN — and "it never ran" usually has more than one cause, only one of which you fixed.** Three co-occurring classes on any guard-fixes-a-guard PR. (a) **Block scoping:** everyone guards the loud `indexOf` failure (`-1` → `slice(start, -1)` widens to the whole file) and misses the silent one — if the delimiter is merely *indented*, `indexOf("\n)")` **skips past it onto the NEXT one, i.e. a sibling block's**, so the extractor over-collects and reports coverage the SUT does not have. Verified: moving 2 of 4 entries into a sibling `WARN_QUERIES` + indenting the paren made the parity test extract 4 while the script summed 2 — the filed bug, reintroduced through its own regression test, green. Require indentation-tolerant delimiters (`/\n[ \t]*\)/`) and mutate a sibling block IN, not just the anchor out. (b) **Latent-vs-operative cause:** a probe committed `100644` is trivially visible and may be entirely *latent* — trace from the INVOKER down (`sweep-followthroughs.sh` enumerates `--label follow-through`; an unlabelled tracker means `run_one` is never called and the `! -x` guard never runs), or the PR ships "now it runs" about a mechanism that has never executed. Don't force-enroll to make the story true — a gate that cannot converge gets bypassed; make the omission legible instead. (c) **Source-level invariants need runtime floors:** `set -u` does NOT abort on an unset associative array (`"${!A[@]}"` iterates 0 times, rc=0, bash 5.3.9), and `[[ -lt ]]` is arithmetic evaluation, so an unvalidated bound (`MIN_SAMPLE=0`/`""`/`"abc"`) silently disables the arm and executes `a[$(cmd)]`. CI parses; the sweeper executes. **Why:** #6435 — all three shipped; the vacuous-GREEN and the false causal claim were caught only by mutating a sibling block in and by tracing the invoker. See `knowledge-base/project/learnings/2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`.

- **A comment/doc fix that asserts "doing X darkens/breaks/removes N of M things" gets the COUNT wrong — and a prescription derived from it can be more harmful than the defect being fixed** — when a PR replaces a false comment, the replacement's most fragile claim is its **arithmetic**, because the N is typically inherited from an upstream doc's singular framing ("remove the fallback **branch**") rather than counted against the M emitters. The review-spawn prompt MUST instruct an agent to enumerate the M and grep each one's emitter/definition. Two free self-checks: (a) if the same comment carries a `NOT affected: …` carve-out, reconcile it against the N — the self-contradiction is often already present in the text; (b) re-derive any prescription ("retire it", "delete it in the same PR") from the corrected count. **Why:** PR #6424 (#6285) — a retirement tripwire claimed *"darkens 3 of the 4 signals … retire that alarm in the SAME PR"*; it darkens **1** of 4 (`ZOT_ACTIVE` occurs 0 times in `cloud-init.yml`, where 2 of the signals live), and retiring would have blinded 3 live signals incl. the alarm's highest-volume one — while the comment's own `NOT darkened:` line already falsified it. `security-sentinel` + `architecture-strategist` converged. See `knowledge-base/project/learnings/2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md`.

- **A self-healing guard that treats "I could not measure" as "the measurement is false"** — when a PR adds an on-host guard that ACTS on a probe (reboot, restart, failover, remediate), the dangerous branch is not the action, it is the guard's own instrument failing. Review must ask, per probe: *what if the binary/endpoint/file the probe reads is simply unavailable — does the guard emit "unknown" or does it emit "absent" and then act?* The canonical instance is PATH: **`ip`, `reboot`, `ip6tables`, `systemctl` live in `/usr/sbin`, which cron's default PATH (`/usr/bin:/bin`) omits — while `curl` (in `/usr/bin`) still resolves.** So under cron the probe returns empty, the *corroborating* signal still works, and the guard acts on a HEALTHY host. Three properties hide it: (a) the boot/`runcmd` invocation runs under a richer PATH, so the post-merge verification passes GREEN and the box pages later, from cron; (b) a test harness that does `PATH="$STUBS:$PATH"` **cannot model a missing binary** — the real one leaks in from the inherited PATH; (c) "the sibling cron proves this shape" transfers nothing if the sibling never used a `/usr/sbin` binary. Reviewer takeaway: for any new cron/systemd consumer, enumerate every binary it calls, `command -v` each, and check the unit/crontab declares a PATH covering all of them; require a fixture that runs with the probe **absent** (stub PATH used ALONE, not prepended) asserting no mutation. Generalizes beyond PATH: *the first consumer of a new dependency class inside an existing pattern inherits none of that pattern's proof.* **Why:** #6415 — the guard would have burned its reboot budget on a healthy registry and then fired a terminal alarm telling the operator to destroy it; `user-impact-reviewer` caught it, 94 green assertions did not. See `knowledge-base/project/learnings/2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`.

- **A test/gate that pins PLACEMENT or EXISTENCE is vacuous w.r.t. the BEHAVIOR the feature exists to provide — mutation-test the property it names, not where the code sits** — when a PR's tests assert *where* a line lives (`indexOf` ordering, a byte-budget, "the emit precedes the reassign") or *that* it exists (`toContain`, an op-contract count), inverting or swapping the implementation's *semantics* can pass every one. The canonical instance: a fresh-boot beacon `if [ "$REF" = "$IMAGE_REF" ]; then _emit A; else _emit B; fi` whose direction (`=` vs `!=`) IS the discriminator — inverting it passed **all 39 tests** and made a soak gate PASS on a fully GHCR-served fleet (a false-PASS on a gate authorizing an irreversible PAT revoke). Reviewer takeaway: for any gate/guard/beacon whose *correctness* is a direction, mapping, or condition (not just its location), require a test that pins the literal behavior AND is **mutation-proven** — invert the operator / swap the branches / delete the guard and confirm the suite reddens. A guard whose deletion leaves the suite green pins nothing; the review-spawn prompt should ask an agent to name the mutation that satisfies the test while violating the property. Adjacent: a body-grep or `indexOf` assertion over a source file must anchor on `^\s*<syntax>` or a call-form, never a bare token that also appears in a COMMENT — the moment a task requires both "assert X" and "document X", they collide (this class recurred **6× in one PR**, and again the day after being documented — the disposition for a recurring documented class is a mechanical gate, not another learning). **Why:** PR #6479 (#6462) — 3 live false-PASS routes (unpinned discriminator direction; `CLOSED`≠fixed; a prose-bypassable corroboration grep) survived a 6-agent plan panel + deepen + TDD + 6-agent review; each was a check certifying the wrong property. See `knowledge-base/project/learnings/2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md` and `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`.

- **A probe/health-check whose fixture models a convenient EXIT CODE instead of the service's real RESPONSE CONTRACT — and the contract is usually already documented in the same file** — when a PR adds a probe against an external service (a registry `/v2/`, a health endpoint, an auth-gated API) and stubs it in tests, the stub reliably models success as "exit 0" while the real service returns something else, so the suite is structurally incapable of observing the defect and every assertion is green over a probe that can never succeed. The canonical instance: zot auth-gates `/v2/`, so an anonymous probe gets **401**; `curl -f` exits **22** on any >=400, so an `-f` probe treats every healthy response as dead. Reviewer takeaway: for any new probe, the spawn prompt MUST instruct an agent to (a) state what the endpoint returns to an **unauthenticated** request and confirm the probe's success predicate accepts it, and (b) `grep the same file` for an existing probe of the same endpoint — the contract is very often already written down within a screen or two (here, verbatim, ~400 lines below: *"401 unauth IS healthy — reachable, auth-gated"*). Also require the stub to model every flag that changes the exit (`-f`, `-w`, `-m`), not just the URL. **Why:** #6537/PR #6540 — the feeder built to arm a 9-day-inert monitor could never emit a beat; 26 assertions certified it; `security-sentinel` + `observability-coverage-reviewer` converged. See `knowledge-base/project/learnings/2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`.
- **A mutation that does not mutate reports a false "the guard works" — assert the mutation LANDED before trusting the run.** A failed `sed` (bad delimiter, drifted anchor, `perl` vs `sed` regex dialect) leaves the SUT pristine, so the suite prints the **baseline** pass-count — which reads exactly like "the guard caught nothing to catch" and is trivially recorded as a passing mutation. It is a *null* result wearing a green result's clothes. Cheapest gate: after applying each mutation, `grep` the mutated token and confirm the file changed (`git diff --quiet <file> && echo "MUTATION DID NOT LAND"`); if a mutation run reports the baseline count, treat it as **un-run**, never as evidence. Applies to the review skill's own mutation-verify guidance above. **Why:** #6537 — an M-B mutation `sed` failed with `unknown option to 's'` and the suite reported 31/0, the exact baseline.
- **`git diff`-based "did it land?" is too weak, and a red BASELINE voids the whole battery — two more ways to record a result that never happened.** (a) A file-level change check proves *something* changed, not that the *right* thing did: a `perl`/`sed` without `/g` replaces the FIRST occurrence, which for any construct you documented in a nearby comment is the **comment**, three lines above the real call site. The file differs, the landing check passes, and the surviving-mutant verdict is fabricated. Assert the *construct* changed — require the old string to occur exactly once before replacing (`n=s.count(old); assert n==1`), or grep the specific call site after the edit. (b) Run the **un-mutated baseline in the same harness first and require it GREEN**: a sandbox that copies only a subtree commonly breaks path/module resolution, and every mutation "result" measured against an already-red baseline is noise that reads like a kill. Same failure surface as the bullet above, opposite cause — there the edit never happened, here it happened in the wrong place. **Why:** #6786 — a sandbox battery ran against a `0 pass/1 fail` baseline (all results void), and the re-run's glob-narrowing mutation edited a comment and was scored as a survivor.
- **A PR whose fix completes POST-MERGE must document it in the future/conditional tense** — when the code lands in one PR but the state-change it enables happens after merge (a reprovision, a backfill, an operator/API arming step, a cutover), the ADR/model/README edits reliably assert the end state as accomplished fact. Nothing catches it: static guards compare source to source, and `ignore_changes`/untargeted resources decouple source from live. If the post-merge phase stalls or is skipped, the repo is left asserting a state that does not exist — which, on a monitor/observability PR, is the very defect being fixed. Reviewer takeaway: when the diff's linked issue has an unchecked post-merge phase, grep the doc edits for present-tense state claims ("is armed", "now pages", "is enabled") and require each to be true **at merge** AND true **if the post-merge phase never runs**. **Why:** #6537 — ADR-096 + `model.c4` said the heartbeat "is armed" while the arming phase was unrun and unrunnable pre-merge; `architecture-strategist` caught it.

- **A drift-guard derives its expected set through the WRONG emitter (so removing scaffolding orders the bug's recreation), and a pinned-artifact delivery certifies the rebuild rather than the bytes** — two shapes that both make a mechanism *look* like it guarantees X while it guarantees Y. (a) **Guard channel-coupling:** when a guard derives an expected set from emitters (`logger -t` tags → an allowlist), an item can be justified by channel B (a unit's `SyslogIdentifier=`, which retags everything the unit writes) yet derived only via channel A (a `logger -t` sitting inside a *cutover-scoped* `sed` replacement). While both coexist the guard looks correct; delete the scaffolding channel later and the item silently drops from EXPECTED, the guard fails, and **its failure text — "array != the logger -t scripts" — instructs the engineer to delete the allowlist entry**, re-blinding the channel the guard exists to protect. Reviewer takeaway: ask *what pulls each item into the expected set, and is that the same thing that justifies it?* — if they differ, the guard is coupled to scaffolding's lifetime; derive EVERY channel independently (before any `continue` gate), and read the failure message as an instruction, because that is what it is — it must name the **emitter** as the source of truth. Prefer a new **derivation** over a new **exemption**: an exemption list is for identifiers no source line can yield (a bare binary basename), so when review deadlocks between "fix it there" and "you can't fix it there", the missing move is usually a third channel, not a bypass. (b) **Pinned-artifact delivery:** "the code is on main" and "the artifact the host boots contains the code" are INDEPENDENT facts. `terraform plan -replace=` force-replaces regardless of any `user_data` diff, so a host rebuilt while its cloud-init still pins a stale OCI tag boots **pre-fix bytes** — a silent no-op that succeeds loudly and **consumes its own rollback window**. Pin guards asserting the pin's *format* and IREF/ZIREF *self-consistency* read exactly like content guards and are not: ask *which of {format, self-consistency, content} does this check?* Require one AC — `git show <pin>:<path> | grep <the fix>` non-zero — for any OCI tag / chart version / AMI / vendored blob. **Why:** PR #6539 (#6536) — the drift guard would have recreated the very 60s failure storm it shipped alongside, and the documented merge→dispatch sequence would have rebuilt the dark host from an image measured to contain none of the fix, spending a zero-downtime window that was free only while the host stayed dark. See `knowledge-base/project/learnings/2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`.

- **A quiesce/drain fix that stops the writer the SYMPTOM named, and a health probe repointed to an endpoint decoupled from the thing being changed** — two shapes that recur together on cutover/migration PRs, and neither is visible to a green suite. (a) **The reported writer is a LOWER BOUND on the quiesce set.** The set is a property of the MOUNT (or table, or queue), not of the units anyone thinks of as "part of the cutover": enumerate *"what else opens, writes, or deletes under this path?"* by grepping every unit/timer/cron/container for the path — a 6-hourly root `rm -rf` timer with no `RequiresMountsFor` produced the IDENTICAL abort signature as the named writer. Stop timers as `<timer> <service>` **pairs** (stopping a `.timer` does not stop the instance it already launched), and re-assert the quiescence gate immediately before the consumer it protects — a single point-in-time sample cannot see a writer that starts in the ~10 minutes after it. (b) **When a probe is repointed, ask what it is COUPLED to, not whether it returns 200.** Replacing a gate that always fails with one that can *never* fail is not a fix: `/health` was `writeHead(200)` unconditionally and the codebase stated a "no mount coupling on /health" invariant explicitly, so it could not fail on the empty-volume case the cutover risks. Prefer the purpose-built readiness endpoint, and order the teardown so the backstop (dead-man, rollback flag) is disarmed **after** the gate it backstops. Corollary: the unit that fails SAFELY is the one WITH the mount requirement — the dangerous one is the unit without it, which starts successfully onto the bare mountpoint. **Why:** #6588 — 8 agents found 4 P1s + a P0 past a 28/28 suite, clean shellcheck and a 191/191 full run; 3 were introduced by the fix. See `knowledge-base/project/learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`.
- **A claim inherited from an earlier phase — a code comment, an ADR line, a plan premise — asserting a wiring that nothing verifies; and its sharpest instance, a wall-clock `break` inside a REPLAYED body.** Four classes recur together on a routine PR whose suite is fully green, because each lives in a seam a test cannot reach by construction. (a) **Replay control flow:** an `elapsed()`/`Date.now()`-derived `break` in an Inngest *body* (not inside a `step.run` callback) re-evaluates on every resume, so after a later loop burns wall-clock a resume re-enters the earlier loop, reads its MEMOIZED verdict, breaks, and terminates on a path whose own step results contradict it — destroying exactly the diagnostic payload the routine exists to capture. ADR-077 bans it; a fake step that runs each callback once cannot model it. Grep every routine body for `Date.now()`-derived control flow. (b) **Third-party envelope shape:** a lifecycle handler's payload often WRAPS the original event (inngest `onFailure` receives `{data:{run_id, error, event:<original>}}`), so reading a flag off the envelope silently returns a default — and the fixture that would catch it was invented by the same author who misread the contract (`event: {}` is a shape production never produces). Read the pinned dependency's `types.d.ts`. (c) **Handler-return projection:** middleware often reads only a NAMED SUBSET of a handler's return (`run-log.ts` projects exactly `{ok, errorSummary}`), so every outcome writes an identical row while a comment claims otherwise — grep the consumer for what it actually reads. (d) **A constant READ but never WRITTEN:** `grep -c` the name; one declaration + one consumer + zero producers means the literal is duplicated at the producer, so rewording it desyncs the guard from its own output while the constant, the consumer and the fixture stay mutually consistent and green. Ask of each: *what would fail if this claim were false?* If the answer is "nothing", it is documentation, not wiring. **Why:** #6698 — all four shipped green (192/192 suites, tsc, semgrep, shellcheck); the replay hazard would have paged on a healthy run, and one review agent independently recommended adding the same construct to a second loop, which would have replicated it. See `knowledge-base/project/learnings/2026-07-19-a-wall-clock-break-in-a-replayed-body-and-a-plan-premise-that-would-have-overridden-the-operator.md`.

- **A scanner allowlist/denylist widened on a property of the MATCHED STRING rather than of the THING being matched — and the doc explaining the rule trips the rule.** When a PR widens a secret-scanner allowlist, a lint suppression, or a WAF/redaction pattern, the justification is almost always a regex-shaped sentence ("terminated by `@`, so it matches only the exact placeholder"). That is a claim about the *string the rule matched*, and it diverges from the security property exactly where the rule's own tokenizer disagrees with a real parser. The review-spawn prompt for `security-sentinel` MUST demand an **adversarial construction attempt** — *"produce an input that satisfies the widened allowlist and is still a real secret"* — because passing fixtures, a mutation-verified test, the plan and the commit message routinely all inherit the same wrong sentence, and N artifacts agreeing is one artifact when they share a premise. Ask, per widening: *which parser's disagreement would break this?* Two companions from the same PR: (a) the artifact DOCUMENTING the rule is itself scanned — a credential-shaped example in a non-allowlisted path reddens the gate, and interpolating a shell variable into the password position does not help (`$`/`{`/`}` are inside the password class); (b) because gitleaks scans the commit RANGE, fixing such a literal at the tip does NOT clear it — that is always a history rewrite. **Why:** #6706/PR #6717 — `pass|passwd|pw` was added to a DSN placeholder allowlist behind an "`@` anchor ⇒ exact match" claim; the rule's `[^@/\s]+` stops at the FIRST `@` while `urlsplit` takes userinfo to the LAST, so `postgres://user:pass@<realsecret>@host` allowlisted itself (measured rc=1 → rc=0 on three realistic shapes). Reverted; the pre-existing half filed as #6723. See `knowledge-base/project/learnings/2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md`.

- **A PR that ADDS a copy of a guarded literal disarms the guard on the ORIGINAL — and its universal negatives are asserted, not enumerated.** Three shapes that co-occur whenever a PR replicates an existing safety mechanism into a sibling job/workflow. (a) **Occurrence-count delta:** guards that assert a literal's *presence* whole-file (`grep -qF "$PAT" "$WF"`, `grep -c … -ge 1`) silently degrade to *first-member* guards the moment the population grows 1 → 2 — deleting the ORIGINAL's clause is then satisfied by the NEW copy, so the original ships fail-open with every coherence check green. The guard is not buggy; the addition broke it. Cheapest gate: `git show origin/main:<f> | grep -cF '<lit>'` vs `grep -cF '<lit>' <f>` — if it grew, every presence-guard over that literal needs re-scoping to the specific member (job-scope it, don't count it). (b) **Universal negatives:** "no automated path can do X" is a claim about a SET; require the diff to carry the WALK (a row per path + its gate), never the conclusion — five artifacts restating one unenumerated claim is ONE artifact, and review must ask "which enumeration produced this?" (c) **Guard tests that certify spelling:** `grep`-based asserts pin CONTENT, and adding an ordering assert pins POSITION — both are spelling. Require the test to EXECUTE the guard (extract the step's own bytes, stub only what needs live state, assert the exit code); litmus: *name a mutation that satisfies the assertion while violating the property.* **Why:** PR #6725 — all three shipped past a 7-agent plan panel, TDD, 193/193 suites and 68/68 CI; the second unguarded `push:main` workflow falsified the PR's central claim within a day, and a self-run 2-mutation battery missed 8 mutants incl. deleting `exit 1`. See `knowledge-base/project/learnings/2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`.
- **A guard whose FIXTURE was drawn from what reads well, not from the production artifact — plus the three vacuities that travel with it.** When a PR adds a guard that compares a live tree/path/table, the fixture is the highest-leverage thing to audit: derive its SHAPE from the production artifact (the cloud-init that creates the dirs, a real listing, the migration) and ask *at the depth/granularity this check runs, is there any reachable state where it says NO?* A `-maxdepth 1` subset check over a tree whose top level is infrastructure (`workspaces/ plugins/ redis/`) and whose identity lives at depth 2 reduces to "does canonical contain a directory named workspaces?" — true in EVERY reachable state, including the one where the stray held a user's only copy, while the depth-1 fixture made the refusal case look covered. Three companions recur in the same diff: (a) **an upstream refusal kills a downstream guard** — `findmnt -no SOURCE "$X"` matches exact mount targets only, so after a `mountpoint -q "$X" && die` above it the operand is unconditionally empty and the check is dead code that reads like a control (a stub contradicting an earlier guard's assertion in the same case, e.g. `MOUNTPOINT_RCS="1 0"` **with** `FINDMNT_STAGING_SRC=$BLKDEV`, is the tell); (b) **function-call coverage is not entrypoint coverage** — a `BASH_SOURCE` sourced-detection guard means no test ever runs the main body, so moving a mutual-exclusion guard BELOW the block whose `exit 0` shadows it leaves the suite fully green (assert call-site ORDER against the file via `grep -n`, failing loudly on a missing anchor); (c) **a mutation that does not land reports a false result in BOTH directions** — assert the mutation landed against a PRISTINE BACKUP (`diff -q "$BAK" "$FILE"`), never against `HEAD` (dirty during any review pass), and treat baseline-identical as UN-RUN, never as evidence. **Why:** #6588/PR #6716 — a self-run 8-mutation battery reported all-caught; 8 agents then found 5 P1s, 4 PR-introduced, on a path that irreversibly deletes user data. See `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`.

- **A repeatedly-firing gate blamed as a false positive, when something upstream is perturbing its input — and the "fix" narrows the gate.** When a PR's premise is "gate G keeps failing on data that looks correct, so loosen G", the review-spawn prompt MUST instruct an agent to enumerate everything that RUNS BETWEEN G's input being finalized and G reading it, and ask *does any of it mutate what G measures?* A gate that has fired N times on byte-identical data is evidence of an upstream perturber, not of a false positive — and narrowing it destroys the one signal that catches the real defect. The tell is a diff whose signature is identical across conditions the author believed were the variable (here: the same `.d..t...... ./` on the wrong device AND the right one, which falsifies device-identity as the cause and points at a *source-side* writer). Two companions: (a) prefer removing the perturbation AT SOURCE over bracketing it — a repair layer needs its own guards, and each guard needs guards (a `touch -r` save/restore + listing fingerprint + read-back + mode split shipped a P1 fail-open where `find`/`sort -z` failure collapsed both fingerprint samples to the empty-input sha, so they compared EQUAL and the guard passed vacuously while telemetry reported clean); (b) ask what disappears STRUCTURALLY under the source fix — a non-writing probe has no residual to document, so every "accepted blind spot" comment the bracket needed becomes unnecessary rather than merely corrected. **Why:** #6733/PR #6735 — the G4 quiescence probe created+unlinked a file inside the rsync transfer root between the delta rsync and C1, advancing the root's mtime; C1 was correct on all five production aborts. Replaced with a read-open (`exec 9<`) + PID-based self-filter, which also fails closed on the absent-`workspaces/` state where the write-probe SUCCEEDS and the cutover ships with every user's data missing. See `knowledge-base/project/learnings/2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong.md`.
- **A fix for a fail-open bug that is itself fail-open — and a weakened default defended by a hazard that already exists on `main`.** When a PR adds a signal whose JOB is to ASSERT something (an artifact landed, a write committed, a consent was recorded), check its INITIAL value: if it starts `true` and is falsified only by an OBSERVED negative, every path that never reaches the observation votes GREEN, so the bug class survives inside its own fix. Ask per signal: *"which code paths set this, and what does it read as on every path that doesn't?"* The tell is a long comment justifying the fail-open default by naming a concrete hazard — **grep whether that hazard already exists on `main`** (`git show main:<file> | grep -n '<the other predicate>'`), because a hazard that predates the change is not a cost the weakening avoids, and the whole trade collapses when it does. The usual remedy is not to weaken the signal but to split the two questions the surrounding helper conflated (here: "what colour do we post" vs "can a replay recover this"); verify the claimed blast radius of that split before accepting a scope objection — a parity test that pins a *gate literal* does not constrain a *helper signature*, and the widening was 6 lines with 7 of 8 cohort callers untouched. **Why:** #6714/PR #6726 — a throw anywhere between `verify-output` and the persistence gate posted a terminal GREEN with nothing committed on the FIRST attempt, verbatim the shape the same PR's ADR-126 forbids; the ADR had to be amended in the same commit because it declared the fail-open default correct. See `knowledge-base/project/learnings/2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact.md`.

- **A differential/comparison gate that silently degrades into a no-op — and a fix for an evidence-discarding gate that discards its own evidence.** When a PR replaces an all-or-nothing gate with a DIFFERENTIAL one (compare A vs B, fail only on a delta), four shapes recur and every one reads green. (a) **The verdict channel eats the evidence:** if the emitter's stdout IS the telemetry stream, a caller writing `verdict="$(emit_and_decide …)"` captures every marker row into a shell variable and the log/off-box sink receive NOTHING — reinstating, inside the fix, the exact defect the PR exists to remove. Litmus: grep whether ANY caller wraps the emitter in `$(...)`; the verdict belongs in a file. (b) **A cap that bounds a capture also bounds the COMPARISON that reads it** — "caps apply to emission only" is the kind of invariant asserted in a comment and false in the code; worse, truncation is asymmetric whenever the two sides' paths differ in length, so the longer-prefixed side loses its tail first and preferentially discards exactly the lines that abort. (c) **A clean verdict is byte-identical to "inspected nothing"** unless something asserts positive work (an object/row/byte count floor); prove it non-vacuous against a loss that emits NO error on either side. (d) **A "could not measure" outcome must be its own ABORTING class evaluated BEFORE the comparison** — if a setup failure looks identical on both sides it classifies as pre-existing, the gate goes green forever, and it inspects zero objects while a later phase deletes the original. Reviewer takeaway: ask "what input makes this gate green while the thing it protects is broken?", and require the exit code to be measured rather than assumed — for `git fsck` (2.53.0) rc is a bitmask, rc 0 does not mean clean, the report spans BOTH streams, and a corrupt loose object exits **rc 128 with a `fatal:`** indistinguishable from a config error, so any classifier keyed on rc or on "has a fatal" is wrong in both directions. **Why:** #6733/PR #6745 — five agents found 6 P1s past a green local driver; the truncation defect alone flipped `copy_corruption` to `preexisting` with truncation as the only variable. See `knowledge-base/project/learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`.
- **A structural guard argued at the SEMANTIC layer but implemented across a re-tokenizing boundary — and a mutation arm whose fixture fails for a SECOND reason proves nothing.** When a PR defends a check by *what shape the data has* ("these appear as nested string content, never as top-level keys"), the argument is only as strong as the layer that preserves that shape: name the tokenizer feeding it and check the layers **below** the one the comment reasons about. Canonical instance: a two-stage `jq -R … | jq -R …` echo-isolation guard — stage 1's `-r` materializes an embedded `\n` as a REAL newline, stage 2's `-R` re-tokenizes on physical lines, and a line from *inside* a multi-line `raw` is then evaluated as a top-level log line, so nesting (the whole basis of the argument) is exactly what the newline strips. Same class wherever a pipeline re-parses its own output: `xargs` on whitespace, `read` on IFS, `sort -u` on embedded newlines, unquoted `for`. Collapse to one pass so the decoded value stays a single value and trailing garbage fails closed. **The companion check is the mutation arm**: it is meaningful only if the fixture would otherwise SUCCEED — if it is rejected for a second, unrelated reason, mutating the guard leaves it rejected and the green is indistinguishable from a real one. Build the fixture ADVERSARIAL (correct in every field the success path reads, except the one under test) and ask *"under the mutated implementation, does this input reach the success path?"*. Adjacent, same PR: `toHaveBeenCalledWith` is EXISTENTIAL, so a mutant that fires a RED heartbeat *alongside* the green one restores the exact bug at 12/12 green — pair it with `toHaveBeenCalledTimes(1)` whenever the contract is "exactly one, and it is this one"; and sample a floor/ceil/round boundary off the midnight multiples where all three coincide. **Why:** #6297 — the anti-echo guard auto-closed a tracker on a forged multi-line row with the credential still unprovisioned; the author's own mutation battery reported all-clear. See `knowledge-base/project/learnings/2026-07-20-my-anti-echo-guard-was-defeated-one-layer-below-the-layer-i-reasoned-about.md`.

- **A deletion PR swept by FILE leaves the twin of every claim it fixed — index the sweep by CLAIM.** When a PR removes an entity (a job, a script, a jq def, an enum value), the reviewer's highest-yield question is not "is each touched file consistent?" but "for each DELETED entity, is every surviving mention historical or a live claim?" A file-indexed sweep is bounded by the diff's file list, so it systematically misses mentions in files the PR never opened — including runbooks, sibling gates, and `.tf` comments — and its failure signature is diagnostic: **the sibling corrected, the twin missed** (the `.jq` generalized but its `web2-retire-gate.sh` twin left; ADR-068 §(c) dated-corrected but the `server.tf` HARD GATE naming the same deleted script untouched). Instruct an agent to enumerate the deleted entities and `grep -rl` each across `*.sh|*.ts|*.tf|*.yml|*.jq|*.md`, excluding plans/specs/brainstorms/archive, then classify every survivor. Also verify any PR-authored claim ABOUT the sweep ("the runbooks were rewritten in the same change") with `git diff --stat -- <path>` — that claim is exactly as likely to be stale as the ones being swept. **Why:** #6575/PR #6744 — 8+ stale claims survived a green 195-suite run, including two live operator instructions that now return HTTP 422. See `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`.

- **A lint/CI gate whose findings are scoped by git history, so it goes vacuous on a shallow checkout and again on its own merge.** When a rule narrows itself to "lines added vs `git merge-base HEAD origin/main`" (a legitimate way to ratchet an accepted population without re-litigating it), its output stops being a function of the code and becomes a function of the repository's history — which fails toward SILENCE in two places no assertion mentions. (1) `actions/checkout` defaults to `fetch-depth: 1`, where `origin/main` does not exist, `merge-base` exits 128, the changed set resolves empty, and every "should fire" assertion fails — or worse, passes vacuously if the suite only asserts rc=0. (2) The suite's own fixtures are COMMITTED, so they read as "added" only until the PR merges; afterwards the diff is empty and the positive arm stops firing permanently. Reviewer takeaway: when a PR adds a gate that shells out to `git` (`merge-base`, `diff --name-only`, `ls-files`), the spawn prompt MUST instruct: *"State what this gate reports on (a) a `fetch-depth: 1` checkout and (b) after this PR merges. If either answer is 'nothing', the scoping is at the wrong layer."* Require history scoping to live ONLY in the repo-sweep mode — an explicitly-named path should be linted whole-file, since naming the path IS the scoping decision — and require the degraded path to WARN that it narrowed, so "no findings" and "could not look" are distinguishable. **Why:** PR #6743 — rule (c) of [scripts/lint-trap-tempfile-ownership.py](../../../../scripts/lint-trap-tempfile-ownership.py) passed 203/203 locally and failed 5/17 in CI on exactly this; fixing only the checkout depth would have left the merge-vacuity defect live. See `knowledge-base/project/learnings/test-failures/2026-07-20-git-diff-scoped-lint-rules-go-vacuous-in-ci-and-on-merge.md`.

- **A correction/replacement PR whose ACs verify the OLD claim is GONE but never verify the NEW claim is SUPPORTED — and an AC that names a sub-region tested against the whole artifact.** When a PR exists to replace a stale or false claim (a competitor figure, a pricing line, a vendor capability, a disclosed retention period), the sweep ACs are all *absence* assertions (`grep -c '<old>' == 0`) and every one can pass while the replacement copy introduces fresh defects — because nothing asserts *presence-with-provenance*. Three shapes recur in the replacement text and all read green: (a) **provenance inversion + metric swap** — the source of truth says "a founder interview *implied* a ~$689K *run-rate*" and the new copy says "third-party reports cite ~$689K in *annual recurring revenue*", hardening an inference into a citation and relabelling the metric, i.e. reproducing the exact defect class the PR exists to fix; (b) **dependent-clause re-pointing** (the `hr`-documented #6538 class, in its *additive* direction) — a clause that was true of the deleted head survives verbatim onto the new head and becomes a non-sequitur ("*growth* validates that founders will pay" → attached to a *funding round*, which is evidence investors EXPECT them to pay); (c) **half-swept sibling** — the published surface is corrected while the upstream row that FEEDS regeneration is not, which is the same mechanism that produced the staleness originally. Reviewer takeaway: require an AC of the form *"every third-party claim the diff ADDS traces to a named line in the cited source of truth"*, and read each rewritten sentence against its new subject rather than diffing tokens. Companion, same PR: when an AC names a sub-region (**"the figure tokens appear in the rendered ANSWER"**), the check must be scoped to that region — a whole-page `grep` passes on tokens sitting in the *question heading* and certifies an answer that has dangling deixis ("that valuation" with no antecedent). Ask of every AC: *does the command's scope equal the noun the AC names?* **Why:** #6768 — all four shipped past a green 11-AC suite and a 204/204 full run; security-sentinel and code-quality-analyst converged on (a), and the author's own AC4 self-report was a false PASS. See `knowledge-base/project/learnings/2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md`.

- **A threshold tested with a population of one, and a red test whose FAILURE MODE regressed while the suite total improved.** Two shapes that travel together on any gate whose verdict is a count. (a) **Threshold coverage:** when the SUT elects on `-gt 0` / `-eq total` / N-of-M, a single-item fixture cannot distinguish ANY of them — `1-of-1` is `all-of-1`. Sweep the suite by fixture SIZE (`grep -c mk_repo` per case, or the equivalent constructor) before believing threshold coverage exists; if every fixture is size 1, the threshold has no test regardless of how many cases pass. Restoring a superseded ALL threshold passed every single-workspace case while turning a 1-of-2 abort into `rc 0, no regression`. (b) **Colour is not a verdict:** a case that stays RED while its recorded rc changes is a finding, and the aggregate can move the other way — a suite going 21/3 → 23/1 concealed one case going from aborting-for-an-unrelated-reason to not-aborting-at-all. Diff **per-case verdicts** across runs, never totals, and never treat a pass-count delta as a safety metric. The enabling defect for both: an assertion that checks *that* the guard fired (`[ "$rc" -ne 0 ]`) rather than *which* guard — in a classifier with several aborting outcomes an exit code is a symptom they all share, so pin the classification string. Corollary for any SYNTHESIZED precondition: synthesizing is right for determinism, but the real contract then exists only in a `printf` the test owns, so re-join it with a conditional assertion on hosts that can produce the real thing (vacuous elsewhere, zero flake). **Why:** #6733/PR #6759 — L6k's `probe_failed` threshold was untested behind six single-workspace fixtures, in the GATE path where a false green precedes wiping the plaintext original; the same pass surfaced `cannot chdir` as dead regex (git emits `cannot change to`). See `knowledge-base/project/learnings/2026-07-20-a-red-test-got-more-dangerous-while-the-suite-pass-count-improved.md`.

- **A stale-claim sweep that marked one block and not its structural twin — look for the ASYMMETRY, not for staleness.** Staleness is not greppable; asymmetry is. When a PR supersedes a decision (a cancellation, a reversal, a deprecation), the same claim usually lives in two or more peer blocks — a ruling in `decision-challenges.md` and its restatement in `session-state.md`, an `## Outstanding` block and a `## Scope Ruling` block in one file, a runbook step and its sibling gate. A sweep indexed by FILE cannot see the peer it did not open the file for, and marking one peer while leaving the other is **worse than marking neither**: a reader infers unmarked = still live. The review-spawn prompt MUST instruct an agent to enumerate the PROPOSITIONS the change falsifies (not the files it edits), `grep -rn` each excluding `archive/`, and classify every survivor as historical-and-marked vs live-and-now-false — then flag any file where one block carries a supersede banner and a peer block does not. Companion, same root: a check whose pattern is DERIVED at runtime (`MARKER=$(grep … file)`) must assert the derivation landed — an empty pattern does not fail loudly (`grep -cF ""` matches every line, most other tools match none), and both outcomes read as a result. **Why:** PR #6784 — the PR existed to remove exactly this defect and reproduced it in the artifact it was fixing, one day after the class was documented; and the fix for a too-narrow AC7 shipped a vacuous bare-ref limb whose `sed` matched nothing. See `knowledge-base/project/learnings/2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md` and `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`.
- **Fixture DIRECTION is the sibling coverage axis: a suite whose fixtures all point one way cannot see the other way, and every mutation you invent lands in the direction you were already thinking about.** When a diff adds a *transform* — a suppression, neutralization, redaction, allowlist, carve-out — check whether ANY fixture sits on the far side of it. The recurring shape is that all N fixtures for the new behavior assert the same outcome (all expect-clean for a suppressor, all expect-flag for a detector), so the suite is structurally blind to the transform being too aggressive, and a green mutation battery says nothing about it. The review-spawn prompt MUST ask: *"name a mutation that makes this transform MORE aggressive — which fixture goes red?"* Two traps when closing it: (a) a fixture that short-circuits on an earlier guard clause never reaches the code under test and pins nothing about the later branch (check which path each fixture actually executes, not just its verdict); (b) a natural-looking delimiter can silently anchor the mutation away — a backticked filename blocks a greedy char-class widening because the backtick is outside the class, so the "obvious" fixture stays green. Two companions from the same session: **a line-level probe is not a valid measurement for a file-scoped scanner** (extracting one line strips it from its enclosing carve-out/fence and flips the verdict — verify in context), and **every comparison arm must be measured on ONE tree** (a pure-removal transform that appears to ADD hits is proof of a broken measurement, not a finding). **Why:** #6771 — the class recurred THREE times in one PR: the tool anchor had zero tests because every positive control contained the word `terraform`; then every filename fixture asserted exit 0, so filename neutralization silenced a genuine `ssh … by hand` runbook step; then the first two over-reach fixtures short-circuited before the char class ran. Three review agents converged where two self-run batteries reported all-caught. See `knowledge-base/project/learnings/2026-07-21-my-fixture-set-had-a-direction-and-both-batteries-were-blind-to-the-other-one.md`.
- **A cloned query/insert idiom whose PRECEDENT table provides something the TARGET does not — and a hand-written fake that cannot reject, so the suite certifies an inert control.** When a PR adds a dedup/idempotency guard by mirroring a sibling call site, the transfer is usually made at the SYNTAX level, and the review-spawn prompt must force it back to the GUARANTEE level: *what does the source table provide that makes this idiom valid, and does the target provide it?* The canonical instance is a `.insert(...).select("id").single()` cloned onto a table whose PK is composite and which has **no `id` column** — PostgREST renders that as `RETURNING id`, the statement fails `42703`, and the insert rolls back, so no marker is ever written. Worse, `42703` is a **plan-time** error, so it fires BEFORE the unique check: even a genuine duplicate returns `42703`, never `23505`, and the suppression branch is unreachable *by construction*. The guard is inert in production with the whole suite green. Three things hide it: an untyped supabase client (no `<Database>` generic, so `tsc` is blind); a fake whose `select` is `vi.fn(chain)` and which keys purely off the insert payload, making it structurally incapable of modelling a column-projection error; and a gated live-DB tier that exercises a call shape production never issues (a *bare* insert), so the one test whose entire job is being ground truth for the mock goes green against the broken code. Reviewer takeaway: for any new fake, demand a **negative control proving it can reject** (a per-table column set + an unknown-column error), and check that the live tier issues the SUT's *exact* chain. Companion, same PR: once the defect is fixed, `grep` the plan and `tasks.md` for the construct — a Risks table still listing the broken idiom as a "live mitigation", and a CHECKED task still mandating it, actively instruct the next author to reintroduce what the branch just paid to find. **Why:** #6781 — 20/20 tests, clean `tsc`, and a self-run M1–M8 mutation battery all reported healthy over a guard that could not fire; three agents converged on it independently. See `knowledge-base/project/learnings/2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it.md`.

See `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` for the full pattern catalogue.

### Sharp Edges: Review Agent Limitations

Review agent suggestions that modify workflow `if` conditions or event filters must be smoke tested against the full user journey (not just the reduced trigger case) before shipping -- agents optimize locally and can break flows they don't fully model.

When a reviewer prescribes `--arg` for jq injection defense in a `gh ... --jq` context, verify the CLI forwards jq flags before implementing. `gh --jq` accepts a single expression string and does NOT forward `--arg`, `--argjson`, or `--slurp` to the underlying jq binary — applying the fix produces `unknown arguments` at runtime. Fall back to shape-validating the shell variable (e.g., `[[ "$VAR" =~ ^[0-9]+$ ]]`) before interpolation, or pipe to a second-stage standalone `jq --arg`. See `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

Generalizing the rule above: whenever a review agent prescribes a CLI flag or subcommand as a fix (e.g., `gh issue create --json number`, `gh issue close --body-file`, `<tool> <subcommand> --<flag>`), verify the flag exists on that exact subcommand via `<tool> <subcommand> --help` BEFORE applying. Agents hallucinate flags by generalizing from sibling subcommands (`gh issue list` has `--json`, `gh issue create` does not). Cost of verification: one `--help` call. Cost of applying a non-existent flag: revert + rework + commit pollution. If the prescribed flag is absent, fall back to a verified pattern (split into two verified commands, parse output with `awk -F/`, etc.) and note the substitution in the disposition table. See `knowledge-base/project/learnings/best-practices/2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md`.

When an agent (or a plan acceptance criterion) claims a syntactic SAST rule will return 0 findings once a guard is added, verify the rule actually models the sanitizer before trusting it. Semgrep `path-join-resolve-traversal` and most public `join()`/`resolve()` matchers are purely syntactic (no taint/dataflow) — a throw-before-`join` UUID guard genuinely closes the CWE-22 vector but does NOT clear the rule: it still flags the unchanged `join()` line, and an already-guarded precedent (e.g. `workspace.ts`) trips the same rule too. Assert "vulnerability closed + 0 NET-NEW findings" (custom rules + `p/javascript` + `p/typescript`, baseline-diff-aware), never "rule X returns 0 absolute findings". **Why:** #5344/#5352. See `knowledge-base/project/learnings/2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md`.

**The registry slugs are `p/javascript` / `p/typescript` — NOT `p/js` / `p/ts`.** This line said `p/js + p/ts` until #6446's review; both 404 (`https://semgrep.dev/c/p/js` → HTTP 404, `p/javascript` → 200). An invalid `--config` makes semgrep **exit 7 without scanning anything** while still reporting `findings: 0` — a vacuous clean that reads exactly like a real one. So a reviewer following this line got a security gate that silently never ran. [semgrep-custom-rules.yaml](./references/semgrep-custom-rules.yaml) already named `p/javascript` correctly, so the two sides of the same skill disagreed. **Always confirm the run was non-vacuous before trusting a clean result** — semgrep prints `Ran N rules on M files`; `N` must be non-zero for the language you are scanning (a real TS scan is ~82 rules). Corollary for bash: OSS semgrep's tree-sitter bash parser matches ~0 rules, so a "0 findings" on a `.sh`-only diff is always vacuous — use `shellcheck` instead.

When a PR's behavior depends on an external-API response shape (Sentry stats buckets, webhook payloads, list-vs-object envelopes, hourly-vs-daily resolution) AND the plan deferred the shape to a "/work will live-probe" AC, do NOT trust a ticked "live-probed" AC or a "verified by probe" code comment — they are claims, not evidence. Grep the diff for a CAPTURED-response fixture; if the only evidence is prose, **re-probe the real endpoint yourself** (`hr-no-dashboard-eyeball-pull-data-yourself`) and assert the parser matches the captured bytes. **Why:** PR #5434 — `sentry-issue-rate` shipped reading `/issues/{id}/stats/?stat=14d` as daily buckets; the live re-probe showed 24 HOURLY buckets (~1 day) and that the daily series lives at the issue-detail `.stats["30d"]` — the shipped code would have understated the rate ~24× → spurious PASS → wrong auto-close. See `knowledge-base/project/learnings/integration-issues/2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim.md`.

The inverse of the rule below is equally load-bearing: **agent convergence is not proof when the agents share a wrong model, and a right verdict can rest on a wrong reason.** Agreement raises confidence only if the errors are independent — when N reviewers inherit one mental model, they are one reviewer. Before counting votes, ask *what model are they all using*, and prefer one irrefutable artifact (a production log, a captured response) over any number of concurring inferences. Two corollaries: (a) **evaluate a verdict separately from its reasoning** — a CONCUR-gate DISSENT can be correct on grounds the dissenter never gave, so reject the model and still accept the call; (b) **a perturbing instrument does not measure the unperturbed system** — `strace`/a debugger/added logging change the timing of the thing being timed, so they detect whether a race WINDOW exists, they do not measure how often it is lost; state which one you ran. **Why:** #6572 — three agents independently called a SIGPIPE defect "latent, not live", all modelling it as needing a full 64 KB pipe buffer (it needs a second `write()`); the issue's own CI log refuted all three, and a fourth agent tried to falsify the two-write model, failed, and reversed itself. Separately an 8 KB producer SIGPIPEd under `strace` yet was 0/200 without it — the instrument, cited as proof of frequency, only ever proved the window. See `knowledge-base/project/learnings/2026-07-16-five-documented-traps-recurred-and-a-perturbing-instrument-is-not-evidence.md`.

When a single agent rates a finding P1/HIGH but no orthogonal agent independently surfaces the same harm, downgrade to advisory or skip. Single-agent HIGH against two-or-more silent or contradicting agents is the modal false-positive pattern. Cross-reconcile triad before applying: a **semantic-quality** agent (code-quality, pattern-recognition), an **orthogonal runtime** agent (performance-oracle for cache/sweep/eviction; data-integrity-guardian for type widening; security-sentinel for trust-surface claims), and **git-history-analyzer** for documented-intent context. Two-of-three concur on "non-issue" → skip with a one-line disposition. The HIGH rating is a hypothesis, not a verdict, and applying a "fix" for a non-issue often re-introduces the complexity the PR was designed to eliminate. See `knowledge-base/project/learnings/2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` (PR #3670 — code-quality flagged a sweep-cutoff change as HIGH "doubles Sentry events"; performance-oracle + git-history-analyzer + dedup-trace independently falsified the claim; the proposed `staleTtlMs` parameter would have re-introduced the per-cache asymmetry the F3 extraction was designed to eliminate).

Parallel review batches can stall silently — spawning 12 review agents at once has been observed to produce completion notifications for only 6, with the remaining agents' transcripts frozen ~15s after spawn and no completion event emitted. When more than 30% of spawned agents stop producing output for >2 minutes after launch, proactively announce "N of M agents stalled" rather than silently waiting. Proceed with synthesis from the agents that returned — the Rate Limit Fallback gate already permits partial coverage. See `knowledge-base/project/learnings/2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md`.

**A MUTATION BATTERY ONLY COVERS WHAT YOU MUTATE — a green battery is evidence about the mutations, not about the tests.** When a PR arrives carrying its own mutation matrix ("each assertion proven RED by relocation; M1 161/164, M2 163/164, …"), that matrix measures the tests against *the mutations its author thought of*, and its green is indistinguishable from the green of a fully-covered SUT. Before crediting it, enumerate the SUT's functions and confirm each appears on the **LEFT of a call** in the test file — `for fn in $(grep -oE '^_[a-z_]+\(\)' src.sh | tr -d '()'); do printf '%-28s %s\n' "$fn" "$(grep -c "${fn} \"" test.sh)"; done` — any `0` is an untested function whatever the battery reported. The review-spawn prompt for `test-design-reviewer` MUST say "find the vacuity the battery MISSED — do not re-run its mutations," and instruct it to mutate a **sandbox copy** (a concurrent in-place mutation is reported by every file-reading agent as a false "uncommitted drift" P1). Companion anchoring rule, same root as the bullet above: an assertion anchored on the shape the code *happens to have* (the verb `printf`, a first-arg-starts-with-`"` call form, one of two sibling emitters) is narrower than the property — invert blacklist→whitelist (strip comments, strip the ONE permitted expansion, assert no `$` survives) so it is verb-blind, line-blind and comment-blind. Litmus: *can you name an implementation a reasonable engineer might write next that satisfies the assertion while violating the property?* **Why:** #6497/PR #6528 — a 7-mutation battery reported 164/165 while `_login_kw`, an entire emitter handling raw credential-adjacent stderr, was called by ZERO tests; mutating it into a Form-A disclosure (raw stderr → journald → Better Stack, unscrubbed, on a live hypothesis path) left the suite BYTE-IDENTICAL. See `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`.

- **The generalized form — ask "what SET does this claim quantify over, and how many members did the test sample?" The class recurred a THIRD time in the same file one round later, so treat prose here as known-insufficient.** Every hole in #6565/PR #6577 reduced to one sentence — *a claim quantified over a set the test only ever sampled once* — and three reviewers converged on it independently. Five instances, all green: "each arm fires" sampled each arm only on ITS OWN fixture (loosening one arm to match a prefix all six fixtures SHARE left the full suite **byte-identical to control**); "`errno_chars` bounds all ~130 errnos" fed **one** errno, so a hardcoded `22` satisfied every assertion; "every arm literal is outside the credential alphabet" read only **single-quoted `case`** arms, so a double-quoted/unquoted/`[[ ]]` arm carried a LIVE credential oracle past a GREEN test; "pull tokens are `[A-Za-z0-9]`" sampled **zot only** (both GHCR PAT formats carry `_`); and an invariant the plan declared "closed" was measured OPEN because it checked the `printf` TOKENS, not the literals. **A positive-only oracle is true of the correct implementation AND of the broken one** — pair every "X happened" with "X happened ONLY where it should", over the WHOLE set. Cheapest mechanical gate, and the tell that the test usually already holds its own disproof: when a test DERIVES a set S from source and asserts a property over S, also assert **S's cardinality matches the producer's** (`[[ "$LIT_N" -ge "$VOCAB_N" ]]`) — a member the extraction cannot see is silently exempt, and that exemption is invisible to every green run. In #6577 the vocab extraction counted 17 while the literal extraction counted 16; the fix compared two integers the test had already computed. See `knowledge-base/project/learnings/2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`.

- **Reconcile a review finding against the artifact BEFORE transcribing it as work — a report is a claim ABOUT a file at a moment, and it goes stale the instant a deepen/rebase/fix pass touches that file.** The repo already applies this to plan-quoted counts, tool-flag units and `session-state.md` decisions; review findings need it too, because the review→consumption gap is exactly where `deepen-plan` runs. **Why:** #6577 — a panel reviewed a PRE-`deepen-plan` revision and reported against its AC numbering; `deepen-plan` then fixed every finding and renumbered, and the findings were transcribed into the plan as "MANDATORY corrections" ordering fixes for things already fixed, citing ACs that no longer existed — asserting-from-a-report in the round whose thesis is "measure, don't infer". Mirror image, same session: a reviewer's first `git diff` calls ran from a drifted CWD and returned a stale tree (5 files/727 lines vs the true 7/789), half-drafting two findings already fixed at HEAD. Both directions: re-derive against the current SHA (`git -C <worktree>`), and treat any agent-reported test count as needing a re-run, not a citation.

A guard's non-vacuity claim is only worth its evidence, and evidence held in session context is uncommitted. When a mutation/RED run proves a guard fails on the catastrophe it exists to catch, **commit the matrix as a harness in the same PR** — do not summarize it in a code comment. A comment reading `mutation-proven` / `verified non-vacuous` / `confirmed RED` asserts a property nothing re-checks: it reads as protection and discourages the next reader from checking, which is worse than saying nothing. Ask of any guard-shaped comment: *if this were false, what would fail?* If the answer is "nothing", replace the adjective with a committed harness. Two construction rules: prove BOTH halves (mutations go RED **and** unmutated/legitimate variants stay GREEN — RED-only evidence cannot distinguish a real guard from one that fires on everything), and mutate a **sandbox copy**, never the tracked file — in-place-mutate + `git checkout --` restore is unsafe to COMMIT (an interrupted CI run leaves the artifact mutated for every later step in the job) even where it is fine for one supervised local run. Check the path filter covers both the harness and the guard it attests. **Why:** #6485 — a laptop crash destroyed an uncommitted M3/M6 mutation matrix mid-VERIFY; the code survived (committed 66s earlier) but the guard's entire value claim did not, and three shipped `mutation-proven 2026-07-15` comments still have no harness behind them. See `knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md`.

- **Fixture SHAPE is a coverage axis that assertion count, parametricity, and mutation score all miss.** A suite can be parametric over every command and binding, carry a fixture-size precondition guard, report a green N-of-N mutation battery — and still be structurally unable to see the mechanism the change exists for, because every fixture is the same *shape*. Canonical instance: a paginating producer emits one array per page, but every fixture held ONE array, under which the flattening (`add // []`) and a first-page-only regression (`.[0] // []`) are indistinguishable; mutating all six sites left the suite 36/36 green while silently undercounting 33%. Before trusting a fixture set, ask *what shapes can the producer emit that no fixture here has?* — multi-page/multi-record is the default miss, and it is invisible to every count-based quality signal. Companion to the mutation-battery bullet above: that one says mutate what the battery missed; this one says the likeliest thing it missed is a shape, not an assertion. **Why:** #6695 — the fix's central mechanism was deletable with the whole suite green. See `knowledge-base/project/learnings/2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`.

**Cheapest prophylactic: `bak=$(mktemp -t review-bak.XXXXXXXX); cp <file> "$bak"; echo "BAK=$bak"` BEFORE the mutation loop, then restore from that echoed `$bak` path** — the "targeted inverse edit" below is correct but error-prone once the file carries a dozen in-flight fixes, and the failure is silent + total. **The backup path MUST be session-unique, and this is the one site where that is load-bearing rather than hygienic:** it is a *restore source*, so a colliding path does not merely clobber a log — it silently restores ANOTHER session's file content over your work. A worktree- or git-dir-scoped path does not help here either, because parallel review agents share ONE worktree (see the concurrency note directly above); only a per-invocation unique path isolates them. **Echo the path** (`echo "BAK=$bak"`): the restore runs in the SEPARATE Bash call mandated below, which does NOT inherit `$bak` — an unechoed `mktemp` value restores `cp "" <file>` (or aborts on `set -u`), so the restore silently never happens and the mutated file survives, the exact loss this prophylactic exists to prevent. **Why:** #6415 — a `git checkout --` restore during a mutation loop wiped ~15 uncommitted review fixes from a test file mid-review; recovery was a full rebuild. Commit the fixes first, or back up, before mutating. **A backup is necessary but not sufficient: put the restore in a SEPARATE Bash call and run the suite under `timeout`.** A mutation that removes a guard can make the SUT *hang* rather than fail (an emptied filename hands awk stdin), the harness then kills the whole call at its own timeout, and a trailing `cp "$bak"` in that same call NEVER RUNS — leaving the mutated SUT on disk while the notification reads like an ordinary timeout. An un-timed harness also reports "still running" instead of a verdict, so the mutation result is lost either way. **Why:** #6454. (The sandbox-copy rule above is the stronger form of this: a mutation that never touches the tracked file has no restore to lose. Keep the backup guidance for the supervised-local case the sandbox rule explicitly still permits.) Mutation-verify restores via `git checkout -- <file>` silently wipe UNCOMMITTED sibling edits in the same file — when a RED-mutation check (operator-run or agent-run) targets a file that also carries uncommitted working-tree changes from the current review pass, `git checkout --` restores to HEAD and deletes the in-flight edit along with the deliberate mutation. Before using `git checkout --` as the undo, check `git status --short <file>`; if the file is dirty beyond the mutation, undo via a targeted inverse edit instead, then grep for the sibling edit's marker to confirm it survived. **Why:** PR #5082 — a noindex RED check on `articles.njk` reverted the same review pass's uncommitted canonical-link fix; caught by a post-restore grep. See `knowledge-base/project/learnings/2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`.

Concurrent mutating agents contaminate the shared worktree — `test-design-reviewer` (and any agent that empirically verifies RED by reverting the production fix in place, then re-running the suite) edits source ON the same worktree the file-reading agents (`data-integrity-guardian`, `architecture-strategist`, `security-sentinel`) are inspecting. When they overlap, the readers observe the transient revert and report it as a HIGH/blocking "uncommitted working-tree / would not compile / fix reverted" finding even though the committed HEAD is correct; an editor or linter watching the worktree can also touch files mid-run. Before trusting ANY such finding, run `git diff HEAD -- <file>` yourself after all agents return — an empty diff means the committed PR is intact and the finding was transient cross-agent contamination, not a defect. Synthesize against the committed HEAD, not the live working tree. **Why:** PR #4767 — two agents independently flagged a test-design-reviewer-induced revert of `byok-resolver.ts` as a blocker; HEAD was correct throughout. See `knowledge-base/project/learnings/bug-fixes/2026-06-02-member-delegation-resolves-active-workspace-not-solo-default.md`.

When a reviewer prescribes adding a PRE-FLIGHT integrity check (a "verify before you mutate" guard) ahead of an operation that REMOVES a redundant/fallback source (a shared override being detached, a dual-write sibling being dropped, a cached value being invalidated), trace which sources satisfy the guard's assertion AT GUARD TIME. If a soon-to-be-removed source is one of them, the pre-flight guard is vacuous — it passes in exactly the dangerous case (it reads through the fallback it is about to delete) and gives false confidence. The load-bearing assertion belongs AFTER the mutation, where only the intended source can satisfy it. Reject the pre-flight suggestion with that rationale and keep the post-mutation eval-verify. **Why:** PR #4619 (#4617) — `flip.sh --detach-shared`; a proposed pre-detach "member enabled=true" check would have passed via the un-removed `org-targeted` override even when `<flag>-orgs` was never provisioned. See `knowledge-base/project/learnings/2026-05-29-pre-flight-integrity-check-through-unremoved-fallback-gives-false-confidence.md`.

When `code-simplifier` returns DISSENT on a bundled scope-out filing, do NOT argue back — read the dissent for the specific finding it cites, flip ONLY that finding inline, and re-run the CONCUR gate on the residual bundle. The gate exists precisely to catch bundling pathology where a single criterion (cross-cutting-refactor, contested-design) gets satisfied by the bundle as a whole while individual items inside it cross the ≤100-line/≤4-file cost-of-filing threshold. Filing the entire bundle inline (out of frustration with the dissent) is also wrong — the residual findings may legitimately scope out. Per-finding triage, not per-bundle. See `knowledge-base/project/learnings/2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md`.

Before reporting a broken link or missing file, reviewer agents MUST verify via Glob or Read. Unverified "broken link" claims waste reviewer-response cycles — the file may exist at the exact path. **Why:** PR #2226 pattern-recognition-specialist false-positive on a `runtime-errors/2026-02-13-...` learning file that did exist.

Before concluding an idiom/symbol is ABSENT from a file via grep, re-check with a multi-line-aware search — a single-line `grep "obj.method("` MISSES line-broken fluent chains (`await expect\n  .poll(...)`, builder chains). Use `rg -U` / `grep -Pzo` or `grep -A1` on the chain head before recommending a change premised on "this idiom doesn't exist here." **Why:** PR #5699 — `code-simplicity-reviewer` claimed "zero existing `expect.poll`" (it existed multi-line at 786/801) and recommended reverting a correct line for the wrong reason. See `knowledge-base/project/learnings/test-failures/2026-06-29-playwright-tohaveclass-auto-retries-poll-swap-is-noop.md`.

When a PR matches ALL of (a) plan reviewed by ≥3 agents at plan time, (b) implementation is verbatim plan execution (no scope creep), (c) diff is dominated by markdown/skill-prose with optional bash marker tests, and (d) no production code paths touched, operator MAY apply a focused 3-agent slice (`pattern-recognition-specialist`, `security-sentinel`, `code-simplicity-reviewer`) instead of the prescribed 8 with explicit deviation rationale in the classification announcement. The 4-class decision tree treats any source extension as `code`, but verbatim prose-plan PRs land in a sub-class where post-implementation review is mostly confirmation — design churn was absorbed at plan time. When in doubt, run the full 8. See `knowledge-base/project/learnings/2026-05-12-post-impl-review-value-asymmetry-for-verbatim-prose-plan-prs.md`.

When reviewing a Nunjucks/Eleventy page that pairs a visible HTML answer with a `FAPage`/`FAQPage` JSON-LD `acceptedAnswer.text`, compare the two surfaces character-for-character per Question. Google's FAQ rich-result parity check compares codepoints — flag (a) `{{ ... }}` interpolation in HTML paired with a hardcoded value in JSON-LD, and (b) HTML entities (`&rsquo;`, `&amp;`, etc.) in one surface and ASCII or `\uXXXX` in the other. See `knowledge-base/project/learnings/2026-04-18-faq-html-jsonld-parity.md`.

When flagging a skill description word-budget overrun, the tokenizer MUST match the CI gate. `plugins/soleur/test/components.test.ts` uses `desc.split(/\s+/).filter(Boolean).length` against the YAML value only (1800-word skill budget); the `grep -h 'description:' | wc -w` pattern in AGENTS.md belongs to the agent 2500-word budget and includes YAML framing, inflating counts by ~5 words per skill. Run `bun test plugins/soleur/test/components.test.ts` before reporting — if it passes, the budget is satisfied. See `knowledge-base/project/learnings/2026-04-19-skill-description-word-budget-tokenizer.md`.

When a review agent reports branch-scope regressions (claims the PR reverts merged commits, touches files outside the PR's linked issue/directory, or shows a file list materially larger than expected), verify with `git diff origin/main...HEAD --name-only` (three-dot) before accepting. Two-dot variants like `git diff main..HEAD` show commits on `main` since the fork point (NOT commits on HEAD) and produce wildly different file lists when the branch is behind main — a common agent failure mode that surfaces as a false-positive P0. See `knowledge-base/project/learnings/2026-04-22-markdown-table-parser-papercuts-and-review-diff-direction.md`.

When a review agent recommends ADDING a field, header, or schema element to a security-relevant surface (wire schema, redaction filter, log scrubber, error envelope), grep the diff scope for `// See #N` provenance comments referencing prior REMOVALS of the same artifact BEFORE applying the fix. A `Pn` rating reflects local severity; it does not auto-override deliberate cross-cutting decisions encoded in code comments. If a prior PR removed the field as a security/privacy mitigation, flip disposition to `contested-design` scope-out with the prior issue # named in the filing — code-simplicity-reviewer reliably co-signs when the threat-model context is surfaced. See `knowledge-base/project/learnings/2026-05-05-agent-native-recommendation-vs-prior-security-removal.md`.

ADRs documenting an *already-chosen-and-shipping* architecture fail `architectural-pivot` — the criterion requires the *fix itself* to change a cross-codebase pattern, and an ADR for the path you're already shipping is documentation work, not pattern-changing work. Inline-absorb ADRs of this shape (~1 markdown file under `knowledge-base/engineering/architecture/decisions/`) rather than scoping them out. Symmetric rule: when `code-simplicity-reviewer` DISSENTs by naming a *different* criterion that fits, re-file under that criterion (fresh concur cycle) rather than absorbing inline — the dissent is on the label, not on the underlying deferral. See `knowledge-base/project/learnings/2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md`.

When `code-simplicity-reviewer` DISSENTs by naming a same-PR inline fix that contradicts an invariant declared in an ADR landed in the same PR, the right disposition is **apply the inline fix AND amend the ADR's invariant in the same commit** — not file the contradiction as a follow-up. Plan-time invariants ("workspace_id immutable", "X is append-only") are hypotheses, not facts; post-implementation review can surface valid carve-outs the plan-reviewer missed (e.g., a downstream cascade DELETE blocked by a new ON DELETE RESTRICT FK). The amendment paragraph in the ADR must cite the DISSENT + the interaction that justifies the carve-out so future readers can trace the why. **Why:** PR #4294 — ADR-039's `workspace_id immutable` declaration would have blocked `anonymise_organization_membership` orphan-cleanup; the DISSENT-flip from scope-out to inline-fix amended the invariant to admit `ON DELETE SET NULL` carve-out. See `knowledge-base/project/learnings/2026-05-22-post-implementation-review-can-amend-plan-time-invariants.md`.

When a reviewer prescribes ADDING a defensive wrapper (try/catch around an SDK call, a typeof guard, a validation step, a retry envelope) citing a single in-tree precedent, grep the same file/module for ≥3 sibling unwrapped invocations of the same primitive BEFORE applying. If precedent is consistent and the new code mirrors it, the wrapper recommendation is precedent-contradicting — reject with a one-line disposition citing the unwrapped sites. The cited precedent may be helper-internal (boot-path safety) and not generalize to call-site code. Cost of verification: one grep. Cost of applying a precedent-contradicting wrapper: a commit that future reviewers will roll back when they apply the same heuristic. See `knowledge-base/project/learnings/2026-05-05-phase-1-instrumentation-when-prior-fix-visibly-missed.md` (#3287 review's false-positive P1 on a `Sentry.addBreadcrumb` call that mirrored 5 in-file precedents).

When a PR introduces a shell wrapper (`with_lock`, `with_lease`, `flock --`, etc.) around a command intercepted by a PreToolUse hook, MUST verify the hook's command-detection regex matches the wrapped form before approving. Cheapest gate: extract the literal `matcher` regex from each `.claude/hooks/*.sh` for the wrapped command, then `echo "$WRAPPED_FORM" | grep -qE "$REGEX" || echo BYPASS`. Hooks anchored to `^|&&|\|\||;` (start-of-line / chain operators) silently bypass when the wrapped form puts the command after a `--` separator inside another argv. The bypass is INVISIBLE in normal review flow because the hook still runs (it just exits 0 without firing) and the wrapped command executes normally. **Why:** PR #3689 — `bash session-state.sh with_lock merge-main 600 -- gh pr merge --squash --auto` silently bypassed `pre-merge-rebase.sh`'s review-evidence gate AND auto-sync, caught only by 11-agent post-implementation review. See `knowledge-base/project/learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md` (SE1).

When a PR changes a command-detection PreToolUse hook's matcher/regex (e.g. `pre-merge-rebase.sh` scoping which strings count as `gh pr merge`), enumerate EVERY input shape the detected command can take and replay each against both the pre-fix and post-fix hook before approving — do not trust the issue's enumerated shapes. For a "command appears inside a commit message" false-positive class, the shapes are: `-m "…"`, `-m '…'`, multi-line `-m`, `-m "$(cat <<EOF … EOF)"` (heredoc INSIDE quotes), AND bare `-F - <<EOF … EOF` (heredoc with an UNQUOTED body). A quote-strip fix covers the first four but silently misses the bare-heredoc body. Also confirm the anti-direction (every real command shape still fires) so the scoping change is not a silent gate-bypass. **Why:** PR #4600 — the plan+work quote-strip handled quoted heredocs but missed the bare `git commit -F - <<EOF` shape (the branch's namesake); `test-design-reviewer` caught it by reconstructing the pre-fix hook and replaying each shape. See `knowledge-base/project/learnings/2026-05-29-command-detection-hook-self-interception-and-heredoc-fp.md`.

When reviewing a Dockerfile + `--entrypoint` invocation pair where the entrypoint script invokes host-management commands (`systemctl`, `journalctl`, `dbus-send`, `mount`, `mkfs`, `apparmor_parser`, `useradd`, etc.), cross-check the base-image package manifest against the script's command invocations. The script's `command -v <cmd>` set OR hard-coded paths (`/usr/bin/systemctl`, etc.) must each appear in either (a) the base image's default package set, (b) an explicit `apk add` / `apt-get install` line in the Dockerfile, OR (c) a bind-mount entry in the container's `docker run` flags. Alpine's `bash curl tar coreutils` baseline does NOT include `systemctl` — it uses OpenRC. A bind-mount of the host's systemd unit directory (etc/systemd/system) to the container DOES NOT install `systemctl` either; only the host's filesystem gets touched, and the script fails at the binary lookup. If the script needs systemd tooling, the canonical fix is content-carrier-only: pull the image, `docker create + docker cp` the script + read pinned ENV via `docker inspect`, `docker rm`, then `sudo -E env ... bash <script>` ON THE HOST. **Why:** PR #3973 — Alpine 3.20 OCI image bundled `inngest-bootstrap.sh`; running it in-container would have failed at `systemctl daemon-reload`. Caught at multi-agent review post-implementation. Full pattern + recovery flow at [`2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`](../../../../knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md).

When invoking the `cross-cutting-refactor` scope-out CONCUR gate, quote the criterion's literal text and demonstrate that the proposed filing matches it word-for-word. The criterion is **directory-scoped** (`core change = files named in the PR's linked issue, OR files in the same top-level directory ... as the primary changed file`), not feature-surface-scoped. Three files under `apps/web-platform/e2e/` are RELATED by the criterion's own definition, regardless of whether they cover different user-facing features (onboarding vs. conversations-rail vs. bubble net). Code-simplicity-reviewer reliably DISSENTs on feature-surface framings, but cheaper to catch in the filing pass — quote the directory anchor explicitly, count files per anchor, and either justify "materially unrelated" with a concrete out-of-directory file list or fix inline. **Why:** PR #3743 PR-A — proposed scope-out filing for a 3-file e2e helper extraction framed unrelatedness as feature-surface (cc-soleur-go vs start-fresh); DISSENT flipped to fix-inline (-184 lines duplicated, +60 lines helper, landed in same PR). See `knowledge-base/project/learnings/2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md` §Session Errors.

**Pipeline-mode rationalization trap.** When all signals appear to align (criterion documented in plan, both reviewers recommend scope-out, finding clearly predates the PR), the temptation to skip the `code-simplicity-reviewer` CONCUR and file directly is exactly the rationalization the gate was designed to prevent. The gate is a hard precondition, not a confidence check — invoke `code-simplicity-reviewer` BEFORE `gh issue create --label deferred-scope-out` regardless of how obvious the criterion seems. See `knowledge-base/project/learnings/2026-05-06-scope-out-second-reviewer-gate-must-precede-filing.md`.

Commit pre-review inline fixes (anti-slop scanner corrections, lint fixes, classification-phase touch-ups) BEFORE spawning the file-reading review agents. An uncommitted working-tree edit is reported as "drift from the committed review target" by every agent that runs `git diff HEAD`, costing one disposition cycle per agent. **Why:** PR #5125 — a BRAND-RAW-HEX tokenization fix sat uncommitted while 12 agents ran; 3 independently flagged it. See `knowledge-base/project/learnings/2026-06-11-worm-mutation-matrix-and-e2e-harness-mock-for-new-fetches.md`.

### Important: P1 Findings Block Merge

Any **P1 (CRITICAL)** findings must be addressed before merging the PR. Present these prominently and ensure they're resolved before accepting the PR.
