---
name: brainstorm
description: "This skill should be used when exploring requirements and approaches through collaborative dialogue before planning implementation."
---

# Brainstorm a Feature or Improvement

**Note: The current year is 2026.** Use this when dating brainstorm documents.

Brainstorming helps answer **WHAT** to build through collaborative dialogue. It precedes the `soleur:plan` skill, which answers **HOW** to build it.

**Process knowledge:** Load the `brainstorm-techniques` skill for detailed question techniques, approach exploration patterns, and YAGNI principles.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to explore? Please describe the feature, problem, or improvement you're thinking about."

Do not proceed until you have a feature description from the user.

## Execution Flow

### Phase 0: Setup and Assess Requirements Clarity

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Read `CLAUDE.md` if it exists - apply project conventions during brainstorming.

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, and `knowledge-base/` exists, create the worktree immediately (pulling Phase 3 forward) so that dialogue and file writes happen on a feature branch. Derive the feature name from the feature description (kebab-case). Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`, then `cd .worktrees/feat-<name>`, then **immediately** run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr` from inside the worktree to push the branch and open a draft PR before any further work. Set `WORKTREE_CREATED_EARLY=true` so Phase 3 skips worktree creation AND skips the duplicate `draft-pr` step. If `knowledge-base/` does not exist, abort with: "Error: brainstorm cannot run on main/master without knowledge-base/. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI). **Why push immediately:** an unpushed feature branch can be wiped by a concurrent session's `cleanup-merged` sweep — the Phase 3 race-window warning applies the same way at Phase 0, just with a longer exposure (Phase 0.1, 0.25, 0.5, 1.0, 1.1, 1.2, and 2 all happen before Phase 3 today). See `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`.

**Plugin loader constraint:** Before proposing namespace changes (bare commands, command-to-skill migration), verify plugin loader constraints -- bare namespace commands are not supported, and commands/skills have different frontmatter and argument handling.

Evaluate whether brainstorming is needed based on the feature description.

**Clear requirements indicators:**

- Specific acceptance criteria provided
- Referenced existing patterns to follow
- Described exact expected behavior
- Constrained, well-defined scope

**If requirements are already clear:**
Use **AskUserQuestion tool** to suggest: "Your requirements seem clear enough to skip brainstorming. How would you like to proceed?"

Options:

1. **One-shot it** - Use the **Skill tool**: `skill: soleur:one-shot` for full autonomous execution (plan, deepen, implement, review, resolve todos, browser test, feature video, PR). Best for simple, single-session tasks like bug fixes or small improvements.
2. **Plan first** - Use the **Skill tool**: `skill: soleur:plan` to create a plan before implementing
3. **Brainstorm anyway** - Continue exploring the idea

If one-shot is selected, pass the original feature description (including any issue references) to `skill: soleur:one-shot` and stop brainstorm execution. Note: this skips brainstorm capture (Phase 3.5), worktree creation (Phase 3), and spec/issue creation (Phase 3.6) -- the one-shot pipeline handles setup through the plan skill.

### Phase 0.1: User-Impact Framing

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every brainstorm MUST surface the framing question before any domain leader is spawned. The point is to force the user-impact lens onto every decision — even ones that look purely technical at first glance.

**Step 1 — Ask the framing question.** Use the **AskUserQuestion** tool to present:

- **Header:** "User impact"
- **Question:** "If this decision ships as designed, what is the worst outcome the target user experiences? If it silently fails, what do they see? If it leaks, what data of theirs is exposed? (Answer even if the request seems purely technical — the framing is the point.)"
- **Multi-select:** false. Use a single free-text answer (the operator may type into the `other` escape if no preset option fits).
- **Options:** the AskUserQuestion tool caps `options` at 4 (`maxItems: 4`), and "Other" is auto-appended by the runtime — do NOT include "Other" in your options list, it wastes a slot. Pick the 3 presets most likely to fit the feature being brainstormed from this menu and let auto-"Other" carry the long tail: "User data exposure", "Credential leak / auth bypass", "Billing surprise / payment error", "Data loss / corruption", "Trust breach / cross-tenant read", "No direct user impact". The free-text answer is what drives Step 2 — presets are scaffolding, not exhaustive.

**Step 2 — Parse the answer for trigger keywords.** Scan the case-insensitive concatenation of (a) the free-text answer and (b) the **endorsed option labels and descriptions** (when the operator picks a preset, multi-options shorthand like "All of them", or any other selection) for any of:

User-data + auth lens:

`data loss` | `trust breach` | `credential exposure` | `credential leak` | `billing surprise` | `user data` | `credentials` | `payment` | `auth` | `session` | `pii` | `private` | `cross-tenant` | `RLS` | `secret` | `secrets` | `token` | `api key` | `api keys` | `webhook`

Infrastructure / data-store lens (covers the #2887 vocabulary the user-data lens alone misses — every term here has a corresponding sensitive-path glob in preflight Check 6):

`migration` | `doppler` | `infra` | `infrastructure` | `terraform` | `firewall` | `dev/prd` | `dev to prd` | `supabase` | `service token` | `service-token` | `rotation` | `rotate` | `byok`

If any keyword matches:

1. Set `USER_BRAND_CRITICAL=true` for the rest of the brainstorm session.
2. Capture a `## User-Brand Impact` block from the answer (artifact named, vector named, threshold inferred — defaulting to `single-user incident` when keywords match) so Phase 3.5 can persist it into the brainstorm document for plan-time carry-forward.
3. Announce: "Tagged as **user-brand-critical**. CPO + CLO + CTO will be spawned in parallel at Phase 0.5 before other specialists. The plan derived from this brainstorm will inherit `Brand-survival threshold: single-user incident` unless overridden."

If no keyword matches:

1. Set `USER_BRAND_CRITICAL=false`.
2. Proceed silently to Phase 0.25.

**Step 3 — Emit telemetry on match.** When `USER_BRAND_CRITICAL=true`, emit rule-application telemetry so the weekly aggregator records that the brainstorm enforcement layer fired (see AGENTS.md `hr-weigh-every-decision-against-target-user-impact`):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-weigh-every-decision-against-target-user-impact applied \
  "Every plan/PR touching credentials, auth, data, paym"
```

Do NOT emit telemetry when `USER_BRAND_CRITICAL=false` — the gate only records when it activates. The aggregate ratio of "fired vs. asked" is itself a signal worth tracking.

**Step 4 — Persist the framing into the brainstorm document.** When `USER_BRAND_CRITICAL=true`, the brainstorm capture in Phase 3.5 MUST include a `## User-Brand Impact` section reflecting the operator's answer (artifact, vector, threshold). The plan skill's Phase 2.6 carries this section forward into the plan, so re-authoring at plan time is unnecessary and risks drift.

**Why:** Triggered by #2887 — the dev/prd Doppler-config collapse shipped because every prior gate weighed the decision on technical and convenience axes only, and no gate asked what one user's data breach would cost the brand. This is the earliest layer of enforcement for the workflow gate; it pairs with plan Phase 2.6 (template), deepen-plan Phase 4.6 (halt), preflight Check 6 (ship gate), and the `user-impact-reviewer` conditional agent to close the loop.

### Phase 0.4: Lane Auto-Detect and Selection

Select an orchestration lane that describes the Phase 0.5 domain-leader breadth. Canonical vocabulary: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## Lane Inference`. Written to spec.md frontmatter at Phase 3.6.

**Skip if** `USER_BRAND_CRITICAL=true` from Phase 0.1 — set `LANE=cross-domain` and proceed to Phase 0.25 without prompting. The framing question was already answered; avoid double-prompting.

**Otherwise:**

1. **Keyword scan** the feature description against the `## Lane Inference` table.

2. **Pipeline / headless mode detection.** If the parent invocation was `/soleur:one-shot`, `/soleur:go --headless`, or any non-interactive context (no TTY available, `HEADLESS_MODE=true`), set `LANE=<keyword-inference-result>` directly — fail-closed to `cross-domain` if no keyword matches. Skip the AskUserQuestion gate. Echo to the operator-facing terminal: `Phase 0.4: pipeline mode — lane=<value> (inferred)`. Continue.

3. **Interactive mode — AskUserQuestion.** Three presets (the runtime appends auto-Other automatically — do NOT include "Other" as a fourth preset per the 4-option cap):
   - Header: `"Lane"`
   - Question: `"Phase 0.5 domain-leader breadth. Inferred: <inferred-lane>."`
   - Options: the three lanes ordered with the inferred lane first labeled `(Recommended)`. Each option's `description` quotes the Phase 0.5 effect from the canonical table.

4. **Resolve response.** If the operator picks a preset, set `LANE=<picked>`. If the operator picks "Other" and the text resolves to a literal lane value, use it. **If "Other" does not resolve, fail-closed:** `LANE=cross-domain` AND echo to operator terminal: `Phase 0.4: free-text "<text>" did not resolve — fail-closed to cross-domain.` (Visible terminal echo, not just artifact note — per spec-flow G3.)

5. **Operator-override telemetry note (FR6).** When the chosen lane differs from the keyword-inferred default, add a one-line bullet to the brainstorm doc body's `## Lane` section: `Lane override: inferred=<inferred>, chosen=<chosen>.` Also echo to operator terminal so the override is visible immediately (not just on doc re-read).

### Phase 0.25: Roadmap Freshness Check

Domain leaders read `knowledge-base/product/roadmap.md` as ground truth. If the roadmap's status columns are stale, every domain assessment is unreliable. This step syncs the roadmap with GitHub milestone data before domain leaders are spawned.

**Skip if** `knowledge-base/product/roadmap.md` does not exist. Topic ("internal tooling", "CLI infra", "developer-tool", "agent infrastructure") is NOT a skip criterion — the milestone count check is cheap, and stale roadmap rows surface as Phase 3.6 friction regardless of brainstorm topic. See `knowledge-base/project/learnings/2026-05-09-brainstorm-skill-heuristics-substring-match-roadmap-skip-cmo-scope.md`.

1. Read the roadmap's `last_updated` frontmatter date.
2. For each phase milestone listed in the roadmap, run `gh issue list --milestone "<milestone name>" --state all --json number,state --jq '.[] | "\(.number) | \(.state)"' | head -n 50` to get current issue states.
3. Compare each issue's GitHub state against the status column in the roadmap table. If any CLOSED issue is listed as "Not started", "Stub only", or "In progress", update it to "Done".
4. Update the `## Current State` section with current open/closed counts per phase.
5. Update `last_updated` and `last_reviewed` frontmatter to today's date.
6. If any changes were made, commit: `git add knowledge-base/product/roadmap.md && git commit -m "docs: sync roadmap statuses from GitHub milestones"`.

**Why:** In #1745, the CPO assessed KB sharing as premature because "KB API and viewer are not started" — but both had been shipping for weeks. The stale roadmap caused a domain leader to give incorrect sequencing advice, wasting a brainstorm cycle.

### Phase 0.5: Domain Leader Assessment

Assess whether the feature description has implications for specific business domains. Domain leaders participate in brainstorming when their domain is relevant.

<!-- To add a new domain: add a row to the Domain Config table below. No other structural edits needed. -->

#### Domain Config

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` now** to load the Domain Config table with all 8 domain rows (Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support). Each row contains: Assessment Question, Leader, Routing Prompt, Options, and Task Prompt.

#### Processing Instructions

Emit rule-application telemetry **only when the brainstorm scope matches the rule's trigger** — i.e., the feature description proposes a new skill, agent, or user-facing capability. For internal infra/CI brainstorms (where the rule does not apply), skip the emit. The telemetry records *rule fires*, not *gate reached* — emitting on every brainstorm pollutes the rule-fire count and breaks the unused-rule reporter.

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-new-skills-agents-or-user-facing applied \
  "New skills, agents, or user-facing capabilities must"
```

0. **Lane-driven domain-set sizing (spec FR4).** Read `LANE` from Phase 0.4.
   - `LANE=procedural`: Skip Phase 0.5 entirely; echo `Phase 0.5: skipped (lane=procedural)` to the operator terminal so the bypass of 8 potential leaders is visible (per spec-flow G2); proceed to Phase 1.
   - `LANE=single-domain`: After step 1 selects the relevant-domain set, spawn only the single highest-relevance leader. On tie at highest score, fall back to **config declaration order** in `brainstorm-domain-config.md` domain table (first match wins). No AskUserQuestion at this point — tie-break is deterministic to support pipeline/headless mode.
   - `LANE=cross-domain`: After step 1, if fewer than 2 domains matched Assessment Questions, expand by adding the next-highest-relevance domain not yet in the set; tie-break by config declaration order; repeat until ≥2 leaders fire. Echo the expansion: `Phase 0.5: cross-domain expansion added <domain> (relevance tied; config-order tie-break)` to the operator terminal (per spec-flow G6).
   - The existing `USER_BRAND_CRITICAL=true` triad override (step 2) wins unconditionally — the triad is always mandatory when set; `LANE` shapes any additional leader inclusion only.
1. Read the feature description and assess relevance against each domain in the table above using the Assessment Question column.
2. **External-product-comparison default:** If Phase 1.0 ran (the feature description references an external platform/product) OR the feature description contains a URL to a competitor's product, treat **CPO and CMO as default-relevant** regardless of the relevance assessment in step 1. External-product comparisons import framing baked in by the comparison source (architecture, target user, positioning); CPO + CMO are the leaders whose first job is to challenge those assumptions before architecture-first leaders (CTO) commit context to designing the wrong product correctly. See `knowledge-base/project/learnings/2026-05-05-brainstorm-spawn-cpo-cmo-early-on-external-product-trigger.md`.
3. For each relevant domain, spawn a Task using the Task Prompt from the table, substituting `{desc}` with the feature description. If multiple domains are relevant, spawn them in parallel. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
4. **In-flight feature refresh:** If the feature description references one or more GitHub issues with an existing plan that carries `brand_survival_threshold` and `## Domain Review (carry-forward)` sections (detect via `gh issue view <N> --json body` + grep for `plan:.*\.md` or by referenced plan path), AskUserQuestion: **carry-forward only** (reuse plan's leader sign-offs verbatim; user-impact-reviewer at PR review remains the load-bearing gate) vs **focused refresh** (spawn leaders with prompts narrowly scoped to: does User-Brand Impact still hold under the new scope decision; any code drift since plan date; one new delta this brainstorm introduces). Cap refresh prompts at 250-350 words per agent; forbid sub-agent spawning. See `knowledge-base/project/learnings/2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md` Pattern 3.
5. If the user explicitly requests a brand workshop or validation workshop (e.g., "start brand workshop", "run validation workshop"), follow the named workshop section below instead of spawning an assessment.
6. If no domains are relevant, continue to Phase 1.

#### Brand Workshop (if explicitly requested)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` now** for the full Brand Workshop procedure (worktree creation, issue handling, brand-architect handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

#### Validation Workshop (if explicitly requested)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` now** for the full Validation Workshop procedure (worktree creation, issue handling, business-validator handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

### Phase 1: Understand the Idea

#### 1.0 External Platform Verification (if applicable)

If the feature description references an external platform, marketplace, or service, **WebFetch the URL first** before launching any research agents. Classify by: (1) self-service or waitlist? (2) discovery surface or procurement layer? (3) does it accept the product category? (4) what are the per-plan quantitative limits? (number of tasks, storage, API calls, concurrent sessions) (5) does the limit cover the migration/feature scope? (6) if the brainstorm is evaluating the candidate as a **replacement** for an existing headless/MCP/CLI integration, does the candidate expose a programmatic surface (MCP server, CLI, or HTTP API) that agents can call without a browser? If no, it is a complement for human-led work, not a replacement — do not spawn agents to design a migration. (7) if the URL points to a third-party Claude Code skill / plugin / vendor-branded repo, run `gh api repos/<o>/<r>/contents/<entry>/SKILL.md --jq .content | base64 -d` to detect vendor-marketing surface (utm-tagged links, vendor logos, "powered by" footers) injected into agent output. Vendor surface is usually localized to README + repo-scan footers — share the contamination map with the user before spawning leaders, and price three options (vendor-as-is / lift-with-MIT-attribution / clean-room) rather than two. This 30-second gate prevents spawning agents that analyze a false premise. **Why:** In #1094, a 9-workflow migration plan was built before discovering the Max plan allows only 3 Cloud scheduled tasks — a limit only discoverable by attempting to create the 4th task or checking via the `RemoteTrigger` API. **Why (6):** #2699 — Claude Design (GUI-only) would have broken `ux-design-lead`, `/soleur:frontend-design`, `/soleur:ux-audit`, and the Product/UX Gate if treated as a Pencil replacement. **Why (7):** 2026-05-09 brainstorm of `gosprinto/compliance-skills` — utm-tagged Sprinto links inside skill description would have leaked operator prompt context to a third party as a *de facto* sub-processor; see `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`.

#### 1.1 Research (Context Gathering)

**Pre-research: check existing KB artifacts first.** Before spawning any agents, run one local check for prior brainstorms and specs matching the feature's topic keywords:

```bash
find knowledge-base/project/brainstorms knowledge-base/project/specs \
  -maxdepth 3 -type f -iname "*<keyword>*" 2>/dev/null | head -n 20
```

If prior artifacts exist, read them and frame the research agent prompts as "given these prior decisions, what's changed and what gaps remain?" rather than "research this topic cold." **Why:** In the 2026-04-17 BYOK usage dashboard brainstorm, the prior `2026-04-10-byok-cost-tracking-brainstorm.md` and `specs/feat-byok-cost-tracking/spec.md` had already decided scope; agents rediscovered them mid-session instead of building on them. See `knowledge-base/project/learnings/2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`. Use `-type f` to avoid false positives from empty spec directories left by prior `worktree-manager.sh feature` runs that bailed before writing spec.md.

**Also check sibling/closed issues for prior framings of the same mechanism.** When the feature_description references `#N` with a parent (`Parent: #M` in the body or an umbrella issue), read the parent's child list AND run `gh issue list --state all --search "<core-mechanism-keywords>"` to surface deferred or closed prior framings. **Why:** 2026-05-11 #2720 brainstorm — the issue was a re-framing of #421 (deferred Layer 2 of self-healing-workflow); without this check, the brainstorm would have produced a parallel spec orphaning #421. See `knowledge-base/project/learnings/2026-05-11-brainstorm-parallel-domain-and-research-fan-out-and-duplicate-issue-discovery.md`.

Run these agents **in parallel** to gather context before dialogue. **Spawn domain leaders (Phase 0.5) and research agents (Phase 1.1) in one parallel batch** via `run_in_background: true` — they're independent. While agents run, use the wait time for local prior-art file checks and parent/sibling issue inspection rather than blocking on a wakeup. **Why:** 2026-05-11 #2720 brainstorm — 4 leaders + 2 research agents in one batch returned in 60-180s vs. ~10 min sequenced.

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, similar features, CLAUDE.md guidance
- **Learnings:** documented solutions in `knowledge-base/project/learnings/` -- past gotchas, patterns, lessons learned that might inform WHAT to build

**Verifying "is X mounted/wired/enabled?" claims.** When a research agent (or your own reasoning) asserts that a component is not present, not mounted, or not wired up, verify by grepping for the **specific consuming symbol** (a variable, hook, state field, or imported component name) rather than relying on absence of a generic phrase. Absence of the feature name in search results is not evidence of absence in code. **Same applies to file-existence claims:** when a subagent reports "file X does not exist on disk," independently verify with `ls <absolute-worktree-path>` from the orchestrator before propagating into brainstorm artifacts — subagent CWD or path-resolution can produce false negatives, particularly across worktree vs. bare-repo paths. **Why:** In the 2026-04-17 session, the Explore agent reported the chat cost badge was "not confirmed to be rendered" because it grepped "cost badge" (no code match); the badge was in fact mounted via `usageData.totalCostUsd` in `chat-surface.tsx`, which a targeted grep for the state identifier would have caught. **Why (file-existence):** 2026-05-10 brainstorm of #2719 — CLO subagent reported `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` missing; compound-time verification found it exists, the false negative had already been written into the brainstorm document and required a correcting edit.

**Verifying "this is a regression of #N" claims.** When the feature description (or your framing) attributes a post-deploy symptom to a recently-merged PR, do NOT accept the attribution until the symptom's trigger path is traced end-to-end: grep the literal rendered string → locate the render condition → identify the state/event that triggers it → cross-check that trigger path against the PR's file diff. If the PR did not modify any file on that path, the symptom is NOT a regression of that PR — it is a distinct latent bug or an adjacent uncovered code path. See `knowledge-base/project/learnings/2026-04-23-verify-trigger-path-before-attributing-regression.md`.

**Verifying referenced PR/issue state.** When the feature description references an adjacent PR or issue (e.g., "PR #N adds X" / "this is the durable fix for #N"), verify the referenced state with `gh pr view <N> --json state,mergedAt` + a grep for the specific symbol the PR is supposed to have introduced (e.g., `git grep -l "<symbol>" main`) BEFORE accepting any sequencing claim from the issue body or weaving it into domain-leader prompts. Issue bodies are written at one point in time and aren't updated when adjacent PRs land or stall. A "PR #N is merged" claim that is false will produce internally-coherent leader recommendations premised on a wrong factual floor (e.g., a CPO "park this" recommendation premised on a bridge fix that hasn't actually shipped). For long-running brainstorms (>30 min between session-start verification and option presentation), re-run the same `gh pr view <N> --json state,mergedAt` check immediately before presenting architecture options whose pros/cons turn on prereq PR state — parallel sessions can merge a prereq mid-brainstorm and dissolve option premises (2026-05-10 #3509 brainstorm: prereqs #3495 and #3508 both merged during the session, dissolving two of three presented options). See `knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md`.

**Verifying "approach 1 vs approach 2" claims.** When the feature description (or the referenced issue body) proposes named architectural approaches AND cites a parent PR or recent commit, grep `main` for the symbol that approach 1 would introduce (a function name, callback hook, or call site mentioned in the issue body) BEFORE Phase 0.5 leader spawn. Presence-on-main is a strong staleness signal — the brainstorm should pivot to *audit residual risk* not *design the fix*. Five seconds at Phase 1.1 saves a multi-leader spawn at Phase 2. This is sharper than the adjacent `gh pr view` check above because an *adjacent* PR (not the cited one) commonly implements the approach. See `knowledge-base/project/learnings/2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md`.

**Treating `claude[bot]` / `bot-fix/attempted` comments as read-only context, not recommendations.** When the issue carries a `bot-fix/attempted` label or `claude[bot]` comment trail, the bot's chosen fix shape optimized for the `fix-issue` skill's single-file constraint — not for brand-survival or user-impact threshold. Read what the bot tried for context, then re-derive the fix shape from leader consensus (Phase 0.5). The bot's "needs multi-file" bail-out is a handoff signal, never an endorsement of the partial shape it attempted. See `knowledge-base/project/learnings/2026-05-07-bot-fix-single-file-constraint-not-a-signal-for-brainstorm-fix-shape.md`.

If either agent fails or returns empty, proceed with whatever results are available. Weave findings naturally into your first question rather than presenting a formal summary.

#### 1.2 Collaborative Dialogue

Use the **AskUserQuestion tool** to ask questions **one at a time**.

**Guidelines (see `brainstorm-techniques` skill for detailed techniques):**

- Prefer multiple choice when natural options exist
- Start broad (purpose, users) then narrow (constraints, edge cases)
- Validate assumptions explicitly
- Ask about success criteria
- If the feature involves an external API, verify its current pricing/tier capabilities via live docs before assuming scope -- model training data is stale for API commercial terms

**Exit condition:** Continue until the idea is clear OR user says "proceed"

### Phase 2: Explore Approaches

Propose **2-3 concrete approaches** based on research and conversation.

For each approach, provide:

- Brief description (2-3 sentences)
- Pros and cons
- When it's best suited

Lead with your recommendation and explain why. Apply YAGNI—prefer simpler solutions.

Use **AskUserQuestion tool** to ask which approach the user prefers.

**Domain re-assessment.** If the scope has materially changed from the original feature description (e.g., from internal tooling to user-facing product feature, or from a single-domain change to a cross-domain capability), re-run Phase 0.5 domain assessment for any domains not already consulted. Scope pivots during brainstorming are common — the domain assessment must reflect the final scope, not just the initial description.

### Phase 3: Create Worktree (if knowledge-base/ exists)

**IMPORTANT:** Create the worktree BEFORE writing any files so all artifacts go on the feature branch.

**If `WORKTREE_CREATED_EARLY=true`** (worktree was created AND pushed via `draft-pr` in Phase 0 branch safety check), skip steps 1-2 AND step 4 below; proceed to step 3 (set worktree path) and continue from Phase 3.5.

**Check for knowledge-base directory:**

```bash
if [[ -d "knowledge-base" ]]; then
  # knowledge-base exists, create worktree first
fi
```

**If knowledge-base/ exists:**

1. **Get feature name** from user or derive from brainstorm topic (kebab-case)
2. **Create worktree + spec directory:**

   ```bash
   ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>
   ```

   This creates:
   - `.worktrees/feat-<name>/` (worktree)
   - `knowledge-base/project/specs/feat-<name>/` (spec directory in worktree)

   **Race-window warning:** Run step 4 (`draft-pr`, which pushes the branch) BEFORE any file writes. An unpushed feature branch can be wiped by a concurrent session's `cleanup-merged` sweep, orphaning any writes to the worktree directory. See `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`.

3. **Set worktree path for subsequent file operations:**

   ```text
   WORKTREE_PATH=".worktrees/feat-<name>"
   ```

   All files written after this point MUST use this path prefix.

4. **Create draft PR:**

   Switch to the worktree and create a draft PR:

   ```bash
   cd .worktrees/feat-<name>
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

   This creates an empty commit, pushes the branch, and opens a draft PR. If the push or PR creation fails (no network), a warning is printed but the workflow continues.

### Phase 3.5: Capture the Design

Write the brainstorm document. **Use worktree path if created.**

**File path:**

- If worktree exists: `<worktree-path>/knowledge-base/project/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md` (replace `<worktree-path>` with the actual worktree path, e.g., `.worktrees/feat-<name>`)
- If no worktree: `knowledge-base/project/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

**Document structure:** See the `brainstorm-techniques` skill for the template format. Key sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

If domain leaders participated in Phase 0.5, include a `## Domain Assessments` section after "Open Questions" with structured carry-forward data for the plan skill:

```markdown
## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### [Domain Name]

**Summary:** [1-2 sentence assessment summary from domain leader]

### [Domain Name]

**Summary:** [1-2 sentence assessment summary from domain leader]
```

- The `**Assessed:**` line lists all 8 domains to confirm completeness
- Only relevant domains get `### [Domain Name]` subsections with summaries
- Omit the entire section if no domain leaders participated

If domain leaders reported capability gaps in their assessments, include a `## Capability Gaps` section after "Domain Assessments" listing each gap with what is missing, which domain it belongs to, and why it is needed. Omit this section if no gaps were reported. **Each capability-gap claim MUST cite specific evidence** (the exact grep / `find` command run, file paths checked, or symbols searched). Bare assertions like "no existing X manages Y" without evidence are research misses, not gaps — the plan-skill's research phase will surface them in a Research Reconciliation table and the plan-time pivot is more expensive than getting the brainstorm grep right. **Why:** PR #3297 — brainstorm declared "no existing Cloudflare Terraform root manages soleur.ai" via a depth-4 `find`; the root existed at `apps/web-platform/infra/` and managed the entire zone, propagating three pivot-required claims into the spec. See `knowledge-base/project/learnings/2026-05-05-brainstorm-capability-gaps-need-repo-grep.md`.

Ensure the brainstorms directory exists before writing.

### Phase 3.6: Create Spec and Issue (if worktree exists)

**If worktree was created:**

1. **Check for existing issue reference in feature_description:**

   Parse the feature description for `#N` patterns (e.g., `#42`). Extract **all** issue numbers found (not just the first — bundle brainstorms commonly reference 3-5 related issues).

   **If one or more issue references found**, validate each via `gh issue view <number> --json state` + `jq .state`:

   - **Single OPEN issue:** Use it as the tracking issue -- skip creation, proceed to step 3 (link artifacts back to this issue).
   - **Multiple OPEN issues (bundle):** Do not create a new umbrella issue. In step 3, append a "Bundled scoping" note linking brainstorm + spec + branch + draft PR to **each** of the referenced issues. The brainstorm/spec themselves serve as the bundle's single source of truth.
   - **If CLOSED:** Warn the user, then create a new issue with "Replaces closed #N" in the body (proceed to step 2).
   - **If not found or error:** Use AskUserQuestion: "Issue #N not found. Create new issue anyway?" If yes, proceed to step 2. If no, abort.

2. **Create GitHub issue** (only if no valid existing issue):

   ```bash
   gh issue create --title "feat: <Feature Title>" --milestone "Post-MVP / Later" --body "..."
   ```

   After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies: `gh issue edit <number> --milestone '<phase>'`.

   Include in the issue body:
   - Summary of what's being built (from brainstorm)
   - Link to brainstorm document
   - Link to spec file
   - Branch name (`feat-<name>`)
   - Acceptance criteria (from brainstorm decisions)
   - If replacing closed issue: "Replaces closed #$existing_issue"

3. **Update existing issue with artifact links** (if using existing issue):

   Fetch the existing issue body with `gh issue view <number> --json body` piped to `jq .body`. Append an Artifacts (or "Bundled scoping") section with links to the brainstorm document, spec file, branch name, and draft PR. Then update with `gh issue edit <number> --body-file -` reading stdin. For bundles, loop over every referenced issue and append the same note to each.

4. **Generate spec.md** using `spec-templates` skill template:
   - Fill in Problem Statement from brainstorm
   - Fill in Goals from brainstorm decisions
   - Fill in Non-Goals from what was explicitly excluded
   - Add Functional Requirements (FR1, FR2...) from key features
   - Add Technical Requirements (TR1, TR2...) from constraints
   - **spec.md frontmatter MUST include `lane: <value>`** where `<value>` is the resolved `LANE` from Phase 0.4. spec.md is the canonical post-Phase-3.6 lane source for downstream `plan` and `work` skills (per `## Lane Inference` carry-forward contract). spec.md frontmatter MUST also include `brand_survival_threshold:` matching the Phase 0.1 framing.

5. **Save spec.md** to the worktree: `<worktree-path>/knowledge-base/project/specs/feat-<name>/spec.md` (replace `<worktree-path>` with the actual worktree path)

6. **Commit and push all brainstorm artifacts:**

   After the brainstorm document (Phase 3.5) and spec are both written, commit and push everything:

   ```bash
   git add knowledge-base/project/brainstorms/ knowledge-base/project/specs/feat-<name>/
   git commit -m "docs: capture brainstorm and spec for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue. The artifacts are committed locally.

7. **Create tracking issues for deferred items:**

   Scan the brainstorm document's Key Decisions table and Non-Goals for items explicitly deferred to a later phase (e.g., "deferred to Phase 3", "revisit when X grows"). For each deferred item, create a GitHub issue:

   ```bash
   gh issue create --title "feat: <deferred item>" --milestone "Post-MVP / Later" --body "Deferred from #<parent-issue> during brainstorm on <date>.\n\n## What was deferred\n<description>\n\n## Why deferred\n<rationale from brainstorm>\n\n## Re-evaluation criteria\n<when to revisit>"
   ```

   After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies. If no items were deferred, skip silently.

8. **Switch to worktree:**

   ```bash
   cd .worktrees/feat-<name>
   ```

   **IMPORTANT:** All subsequent work for this feature should happen in the worktree, not the main repository. Announce the switch clearly to the user.

9. **Announce:**
   - If using existing issue: "Spec saved. **Using existing issue: #N.** Now working in worktree: `.worktrees/feat-<name>`. Use `skill: soleur:plan` to create tasks."
   - If created new issue: "Spec saved. GitHub issue #N created. **Now working in worktree:** `.worktrees/feat-<name>`. Use `skill: soleur:plan` to create tasks."

**If knowledge-base/ does NOT exist:**

- Brainstorm saved to `knowledge-base/project/brainstorms/` only (no worktree)
- No spec or issue created

### Phase 4: Handoff

**Execute concluded actions first.** If the brainstorm concluded with an immediate actionable step (subscribe to a service, configure a tool, open a page), execute it via Playwright, `xdg-open`, CLI, or API before presenting handoff options. Do not list it as a prose "action item."

**Exit gate sequence:**

1. Run `skill: soleur:compound` to capture learnings from the brainstorm session.
   If compound finds nothing to capture, it will skip gracefully — do not block on this.
2. Commit and push any remaining uncommitted artifacts. Scope `git add` to
   feature-specific directories only (do NOT use `git add -A knowledge-base/`
   which could stage unrelated changes from other worktrees or manual edits):

   ```bash
   git add knowledge-base/project/brainstorms/ knowledge-base/project/specs/feat-<name>/
   git status --short
   ```

   If there are staged changes, commit with `git commit -m "docs: brainstorm artifacts for feat-<name>"` and `git push`.
   If push fails (no network), warn and continue.

Display the resume prompt (per AGENTS.md Communication rule). Format:

```text
All artifacts are on disk. Run `/clear` then paste this to resume:

/soleur:plan #<issue-number> - <feature title>. Brainstorm: <brainstorm-path>. Spec: <spec-path>. Worktree: <worktree-path>

Context: branch <branch>, PR #<N>, issue #<N>.
Brainstorm complete with <N> key decisions. Ready for planning.
```

Replace placeholders with actual values from the session.

**Resume prompt (MANDATORY):** After the display message above, always output a copy-pasteable resume prompt block. This is required by AGENTS.md whenever `/clear` is mentioned. Format:

```text
Resume prompt (copy-paste after /clear):
/soleur:plan #<issue-number> — <feature title>. Brainstorm: <brainstorm-path>. Spec: <spec-path>. Branch: feat-<name>. Worktree: .worktrees/feat-<name>/. PR: #<pr-number>. Brainstorm complete, plan next.
```

Use **AskUserQuestion tool** to present next steps:

**Question:** "Brainstorm captured. Resume prompt above. What would you like to do next?"

**Options:**

1. **Proceed to planning** - Use `skill: soleur:plan` (will auto-detect this brainstorm)
2. **Create visual designs** - Run ux-design-lead agent for .pen file design (requires Pencil extension). The agent auto-opens the screenshots folder for founder review after completion. **Do NOT supply output paths in the spawn prompt** — the agent owns the path convention (`knowledge-base/product/design/{domain}/`). Passing app-tree paths (e.g., `apps/web-platform/design/`) breaks `/soleur:ux-audit` discoverability and is silently gitignored by app-level rules. The agent's output-path guard will override invoker-supplied paths and announce the override.
3. **Refine design further** - Continue exploring
4. **Done for now** - Return later

## Output Summary

When complete, display:

```text
Brainstorm complete!

Document: knowledge-base/project/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md
Spec: knowledge-base/project/specs/feat-<name>/spec.md
Issue: #N (using existing) | #N (created) | none
Branch: feat-<name> (if worktree created)
Working directory: .worktrees/feat-<name>/ (if worktree created)

Key decisions:
- [Decision 1]
- [Decision 2]

Next: Use `skill: soleur:plan` when ready to implement.
```

**Issue line format:**

- `#N (using existing)` - When brainstorm started with an existing issue reference
- `#N (created)` - When a new issue was created
- `none` - When no worktree/issue was created

## Managing Brainstorm Documents

**Update an existing brainstorm:**
If re-running brainstorm on the same topic, read the existing document first. Update in place rather than creating a duplicate. Preserve prior decisions and mark any changes with `[Updated YYYY-MM-DD]`.

**Archive old brainstorms:**
Run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/project/brainstorms/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "brainstorm: archive <topic>"`.

## Important Guidelines

- **Stay focused on WHAT, not HOW** - Implementation details belong in the plan
- **Ask one question at a time** - Don't overwhelm
- **Apply YAGNI** - Prefer simpler approaches
- **Keep outputs concise** - 200-300 words per section max

NEVER CODE! Just explore and document decisions.
