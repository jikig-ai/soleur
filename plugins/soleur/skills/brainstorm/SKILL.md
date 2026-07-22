---
name: brainstorm
description: "This skill should be used when exploring requirements and approaches through collaborative dialogue before planning implementation."
---

<!-- brainstorm-anti-bypass-protocol:start -->
## Anti-bypass protocol (load-bearing — especially Grok Build)

You are the **exploration orchestrator**. Whether entered via `/go` (default route) → `/brainstorm` or direct `/brainstorm`:

- **FORBIDDEN:** Product code (Write/Edit/Shell on implementation files). Brainstorm answers **WHAT**, not **HOW**.
- **FORBIDDEN:** Ending after spec/brainstorm doc without a lifecycle handoff — artifacts alone are not deliverables.
- **REQUIRED (Grok Build):** Invoke successors via slash commands — `/plan` (default) or `/one-shot` (when requirements are already clear). Do not read their SKILL.md and improvise.
- **Harness adapter:** `plugins/soleur/lib/harness.ts` — Grok uses `/plan`, `/one-shot`; Claude uses Skill tool (`soleur:plan`, `soleur:one-shot`).

See `plugins/soleur/lib/workflow-fidelity.ts` (`BRAINSTORM_CHILD_SKILLS`) and `go.md` Step 2.1 (`go-post-route` block).
<!-- brainstorm-anti-bypass-protocol:end -->

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

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, and `knowledge-base/` exists, create the worktree immediately (pulling Phase 3 forward) so that dialogue and file writes happen on a feature branch. Derive the feature name from the feature description (kebab-case). Run `SOLEUR_SKILL_NAME=brainstorm SOLEUR_EXPECTED_DURATION_MIN=60 ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh feature <name>` (env vars wire a session lease that blocks sibling cleanup-merged from reaping this worktree), then `cd .worktrees/feat-<name>`, then **immediately** run `bash ${CLAUDE_PLUGIN_ROOT:-../../plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh draft-pr` from inside the worktree to push the branch and open a draft PR before any further work. Set `WORKTREE_CREATED_EARLY=true` so Phase 3 skips worktree creation AND skips the duplicate `draft-pr` step. If `knowledge-base/` does not exist, abort with: "Error: brainstorm cannot run on main/master without knowledge-base/. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI). **Why push immediately:** an unpushed feature branch can be wiped by a concurrent session's `cleanup-merged` sweep — the Phase 3 race-window warning applies the same way at Phase 0, just with a longer exposure (Phase 0.1, 0.25, 0.5, 1.0, 1.1, 1.2, and 2 all happen before Phase 3 today). See `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`.

**Pre-worktree premise probe (stale "doesn't exist" / "blocked by" / "deferred from" / "after PR #N" claims).** BEFORE pulling Phase 3 forward, if the feature description contains a `#N` reference AND `gh issue view <N> --json body` body contains literal text matching `does not yet exist` OR `deferred from #?\d+` OR `blocked by #?\d+` OR temporal-precondition framings `(after|when|gated on|pending) PR #?\d+ ?(merges|lands|ships|is merged)?`, probe each cited reference: try `gh pr view <ref> --json state,mergedAt` first (the cited `#N` is often a PR not an issue, and `mergedAt` is the load-bearing field — a PR can be CLOSED-not-merged), fall back to `gh issue view <ref> --json state,closedByPullRequestsReferences` on PR-lookup failure; AND `git show origin/main:<named-artifact>` (NOT bare-repo `ls`) for any artifact path cited in the issue body. The bare repo's working tree can lag `origin/main` and produce false-negative "missing" results for files that exist at the canonical ref — propagating into a wrong-premise re-framing. If `git show` fails, defer the artifact-existence check until after the worktree is created and re-grep from inside it. If ALL cited blockers are CLOSED / referenced PRs are MERGED and ALL named artifacts exist, the premise is stale — re-frame with the user BEFORE creating the worktree. **Why:** #3987 stale-claim case; #4078 bare-root false-negative for cited `2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md`; #4319 temporal-precondition miss where "After PR #4289 merges" framing wasn't matched by the status-verb regex and PR #4289 had already merged 2026-05-22T08:07Z by brainstorm time. See `knowledge-base/project/learnings/2026-05-18-premise-validation-and-multi-clause-predicate-reading.md`, `knowledge-base/project/learnings/2026-05-21-brainstorm-premise-verification-call-site-granularity-and-adr-mutability.md`, and `knowledge-base/project/learnings/2026-05-22-brainstorm-precondition-pr-merge-gate.md`. **Forward-companion canary:** the regex above is backward-looking; a *forward* reference to an unlinked companion ("Companion PR (creates X): to be linked", "seeded under a separate PR") is a distinct canary it misses — the companion is filed to land in parallel and on a fast repo routinely merges BEFORE the brainstorm runs. When an issue frames work as "create X" AND cites a not-yet-linked companion that creates X, run `git show main:<X>` + `gh pr list --state all -L 200 --search "<X>"` before accepting the greenfield framing; if X exists, the real scope is the remainder the issue tracks, not X. **Why:** #5754 — register `domain-model.md` already existed via companion PR #5773 (merged the prior day); greenfield framing would have re-built it. See `knowledge-base/project/learnings/2026-07-01-brainstorm-companion-pr-to-be-linked-already-merged.md`.

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

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every brainstorm is **unconditionally treated as user-brand-critical** before any domain leader is spawned. Per #5175 (operator decision from the #5085 brainstorm): the operator always answered the prior framing question with "all of them," so prompting added friction without ever changing the posture. The user-impact lens is now forced onto every decision by default — there is no question to ask.

**Step 1 — Set the flag unconditionally (no prompt, no parse).** Set `USER_BRAND_CRITICAL=true` for the rest of the brainstorm session. Do NOT present an `AskUserQuestion`; do NOT scan the request for trigger keywords. The always-on posture is intentional — it over-protects (fail-safe direction) rather than risk under-protecting a feature whose impact looks purely technical at first glance.

**Step 2 — Synthesize the `## User-Brand Impact` block.** Capture a `## User-Brand Impact` block so Phase 3.5 can persist it into the brainstorm document for plan-time carry-forward:

- **Artifact:** the feature's named surface — derive it dynamically from the feature description / `$ARGUMENTS` (the concrete thing being built, e.g. "the X endpoint", "the Y skill"). This MUST be the real surface, never a static literal — a concrete artifact keeps plan-time carry-forward and the `user-impact-reviewer` honest, preventing the always-on default from degrading into a rubber stamp.
- **Vector:** a single generic exposure-vector sentence (worst-case data exposure / silent failure / trust breach for the named artifact).
- **Threshold:** `single-user incident`.

Then announce: "Tagged as **user-brand-critical** (auto, per #5175). CPO + CLO + CTO will be spawned in parallel at Phase 0.5 before other specialists. The plan derived from this brainstorm will inherit `Brand-survival threshold: single-user incident` unless overridden."

**Step 3 — Emit telemetry.** Emit rule-application telemetry so the weekly aggregator records that the brainstorm enforcement layer fired (see AGENTS.md `hr-weigh-every-decision-against-target-user-impact`):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-weigh-every-decision-against-target-user-impact applied \
  "Every plan/PR touching credentials, auth, data, paym"
```

The gate now fires on every brainstorm by design (per #5175), so this emit records every application of the rule. Accepted tradeoff: the "fired vs. asked" ratio is now constant (always fired) — that diagnostic signal was deliberately traded away for zero operator friction. Do NOT delete the emit; the per-application record is still consumed by the weekly aggregator.

**Step 4 — Persist the framing into the brainstorm document.** The brainstorm capture in Phase 3.5 MUST include a `## User-Brand Impact` section reflecting the synthesized framing (artifact = the feature's named surface, vector = generic, threshold = single-user incident). The plan skill's Phase 2.6 carries this section forward into the plan, so re-authoring at plan time is unnecessary and risks drift.

**Why:** Triggered by #2887 — the dev/prd Doppler-config collapse shipped because every prior gate weighed the decision on technical and convenience axes only, and no gate asked what one user's data breach would cost the brand. This is the earliest layer of enforcement for the workflow gate; it pairs with plan Phase 2.6 (template), deepen-plan Phase 4.6 (halt), preflight Check 6 (ship gate), and the `user-impact-reviewer` conditional agent to close the loop. #5175 made the gate unconditional — the operator's standing "all of them" answer is encoded as an always-on default, removing the per-brainstorm prompt while preserving (and strengthening) the always-protective posture.

### Phase 0.4: Lane Auto-Detect and Selection

Select an orchestration lane that describes the Phase 0.5 domain-leader breadth. Canonical vocabulary: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## Lane Inference`. Written to spec.md frontmatter at Phase 3.6.

**Skip if** `USER_BRAND_CRITICAL=true` from Phase 0.1 — set `LANE=cross-domain` and proceed to Phase 0.25 without prompting. Phase 0.1 now sets this unconditionally (per #5175), so the lane is always fixed to `cross-domain` here; there is no framing prompt to double up on.

**Otherwise** (vestigial fallback — under #5175 Phase 0.1 sets `USER_BRAND_CRITICAL=true` unconditionally in every mode, so the skip above always fires and this block is currently unreachable; retained as the escape hatch for any future per-feature `USER_BRAND_CRITICAL` override):

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
2. **Detect drift via the shared reconcile module** (read-only — one parser, shared with `/soleur:product-roadmap validate`): `bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/product-roadmap/scripts/roadmap-reconcile.sh validate`. It emits `STALE_STATUS` / `MISSING_ISSUE` / `EMPTY_MILESTONE` verdicts naming each drifted phase + the milestone's live open/closed counts. (This replaces the previous hand-rolled per-milestone `gh issue list` loop, so detection logic lives in exactly one place.)
3. For each `STALE_STATUS` verdict, update that phase's `## Current State` count cell to the milestone values the verdict reports. If any CLOSED issue is listed as "Not started", "Stub only", or "In progress", update it to "Done".
4. Update `last_updated` frontmatter to today's date **only** — a reconcile is an automated write, never a human review, so it must NOT bump `last_reviewed` (that would silently reset the roadmap's review clock; ADR-094).
5. If any changes were made, commit: `git add knowledge-base/product/roadmap.md && git commit -m "docs: sync roadmap statuses from GitHub milestones"`. (Freshening before leaders spawn is a narrow count-sync write, distinct from the report-only `validate` skill.)

**Why:** In #1745, the CPO assessed KB sharing as premature because "KB API and viewer are not started" — but both had been shipping for weeks. The stale roadmap caused a domain leader to give incorrect sequencing advice, wasting a brainstorm cycle.

### Phase 0.4: Linear Context Preflight

Scan `$ARGUMENTS` for substrings matching `[A-Z]{2,}-[0-9]+` or `linear\.app/[^/]+/issue/`. If any match:

1. Use the **Skill tool**: `skill: soleur:linear-fetch`, args: "$ARGUMENTS". The skill returns two artifacts: `agent_context` (the markdown blob + image content blocks, streamed into THIS brainstorm conversation only) and `persist_safe_summary` (the same text with every `uploads.linear.app/*` URL redacted to `[linear-image: REDACTED]`).
2. The brainstorm parent conversation retains `agent_context` for Phase 2 Synthesis and Phase 3 Capture — when synthesizing or writing the brainstorm doc, you may reference the visual content directly but MUST NOT write any `uploads.linear.app` URL into the brainstorm file. Use `persist_safe_summary` for any direct quotation of issue body text in the brainstorm doc.
3. When Phase 0.5 spawns domain leaders via Task, embed `persist_safe_summary` (NOT `agent_context`, NOT `$ARGUMENTS`) in the leader prompt's context section. Task subagents inherit prompt text only — they do not receive image content blocks (see `knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`). The leaders' assessment will be text-only-aware; the brainstorm parent retains the visual context for its own synthesis.

Phase 0.4 must complete before Phase 0.5 spawns leaders. The two phases are sequential despite Phase 0.5 internally parallelizing leader spawns. If no Linear references match in `$ARGUMENTS`, Phase 0.4 is a no-op and the brainstorm proceeds directly to Phase 0.5 unchanged.

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
3. For each relevant domain, spawn a Task using the Task Prompt from the table, substituting `{desc}` with the feature description. **When the feature is anchored on a specific prospect or customer signal, gather verifiable facts about them (headcount, named roles, employment relationship vs. retainer/advisor) BEFORE spawning leaders and thread these facts into every Task Prompt alongside `{desc}` — quotes alone admit multiple readings that leaders may resolve confidently in the wrong direction** (see `knowledge-base/project/learnings/2026-04-27-prospect-anchored-brainstorm-fact-loading.md`). If Phase 0.4 fired (Linear references detected and `linear-fetch` returned a `persist_safe_summary`), the `{desc}` substitution MUST use `persist_safe_summary` in place of the raw `$ARGUMENTS` — never the `agent_context` artifact, never a `uploads.linear.app` URL. If multiple domains are relevant, spawn them in parallel. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
4. **In-flight feature refresh:** If the feature description references one or more GitHub issues with an existing plan that carries `brand_survival_threshold` and `## Domain Review (carry-forward)` sections (detect via `gh issue view <N> --json body` + grep for `plan:.*\.md` or by referenced plan path), AskUserQuestion: **carry-forward only** (reuse plan's leader sign-offs verbatim; user-impact-reviewer at PR review remains the load-bearing gate) vs **focused refresh** (spawn leaders with prompts narrowly scoped to: does User-Brand Impact still hold under the new scope decision; any code drift since plan date; one new delta this brainstorm introduces; **does any inherited transparency/disclosure surface (banner, blast notification, in-product banner) still match THIS PR's audience — drop if the affected cohort is reachable by a cheaper, more honest channel** per `knowledge-base/project/learnings/2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md`). Cap refresh prompts at 250-350 words per agent; forbid sub-agent spawning. See `knowledge-base/project/learnings/2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md` Pattern 3.
5. If the user explicitly requests a brand workshop or validation workshop (e.g., "start brand workshop", "run validation workshop"), follow the named workshop section below instead of spawning an assessment.
6. If no domains are relevant, continue to Phase 1.

#### Brand Workshop (if explicitly requested)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` now** for the full Brand Workshop procedure (worktree creation, issue handling, brand-architect handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

#### Validation Workshop (if explicitly requested)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` now** for the full Validation Workshop procedure (worktree creation, issue handling, business-validator handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

### Phase 1: Understand the Idea

#### 1.0 External Platform Verification (if applicable)

If the feature description references an external platform, marketplace, or service, **WebFetch the URL first** before launching any research agents. Classify by: (1) self-service or waitlist? (2) discovery surface or procurement layer? (3) does it accept the product category? (4) what are the per-plan quantitative limits? (number of tasks, storage, API calls, concurrent sessions) (5) does the limit cover the migration/feature scope? (6) if the brainstorm is evaluating the candidate as a **replacement** for an existing headless/MCP/CLI integration, does the candidate expose a programmatic surface (MCP server, CLI, or HTTP API) that agents can call without a browser? If no, it is a complement for human-led work, not a replacement — do not spawn agents to design a migration. (7) if the URL points to a third-party Claude Code skill / plugin / vendor-branded repo, run `gh api repos/<o>/<r>/contents/<entry>/SKILL.md --jq .content | base64 -d` to detect vendor-marketing surface (utm-tagged links, vendor logos, "powered by" footers) injected into agent output. Vendor surface is usually localized to README + repo-scan footers — share the contamination map with the user before spawning leaders, and price three options (vendor-as-is / lift-with-MIT-attribution / clean-room) rather than two. This 30-second gate prevents spawning agents that analyze a false premise. **Why:** In #1094, a 9-workflow migration plan was built before discovering the Max plan allows only 3 Cloud scheduled tasks — a limit only discoverable by attempting to create the 4th task or checking via the `RemoteTrigger` API. **Why (6):** #2699 — Claude Design (GUI-only) would have broken `ux-design-lead`, `/soleur:frontend-design`, `/soleur:ux-audit`, and the Product/UX Gate if treated as a Pencil replacement. **Why (7):** 2026-05-09 brainstorm of `gosprinto/compliance-skills` — utm-tagged Sprinto links inside skill description would have leaked operator prompt context to a third party as a *de facto* sub-processor; see `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`.

<!-- DIVERGENCE per #3836: trigger predicates and exit branches made explicit for Phases 1.0.5 + 2.5 (from #2733 verbatim) and the Phase 2 inline Budget checkpoint paragraph. Spec-flow-analyzer Flows 1-5 from PR #3808 plan-review. -->

#### 1.0.5 Premise Validation

If the feature description references named external systems, prior issues, prior brainstorms, or numerical claims (caps, counts, byte budgets), grep existing truth sources (CI report, roadmap, prior brainstorms) for those named entities or claims before launching research agents. Three exit branches: (a) confirmed → proceed to 1.1; (b) contradiction → re-scope with the operator and restart 1.0.5 on the revised framing; (c) operator override → annotate the disagreement in the brainstorm body and proceed. A framing defect caught here is worth more than a full research sprint built on it.

**An issue's archaeology — *why* the current state exists — is a claim to VERIFY against the PR that made it, not context to accept.** When the feature description explains current state with speculative-causality language ("probably", "almost certainly", "(probable)", "became permanent", "the workaround stuck", "at some point someone", "presumably"), the author is *reconstructing*, not reporting — the hedge is the trigger token. Verify BEFORE it bounds the option space: `git log -1 --format='%H %ad %s' --date=iso -L <start>,<end>:<path>` on the state's own lines, or `gh pr list --state all -L 200 --search "<the thing that moved>"` → `gh pr view <N> --json title,mergedAt,body`. A **deliberate decision and an accident have opposite fixes** — the accident framing makes "revert it" read as cleanup when it is actually undoing a working fix, and a PR merged BEFORE the issue was filed settles it. The PR *title* is the cheapest intent oracle in the repo and is almost never consulted. **Why:** #6538 — "web-2 was almost certainly placed in fsn1 as a stock workaround … The workaround became permanent"; PR #6393, merged three days BEFORE the issue was filed, is titled "relocate warm-standby web-2 hel1→fsn1 (cross-DC HA)" with the rationale recorded in both `variables.tf` and `server.tf`. The issue's recommended option would have reverted a 3-day-old fix for a repo-wide apply wedge. See `knowledge-base/project/learnings/workflow-patterns/2026-07-16-issue-archaeology-is-a-claim-verify-against-the-pr-that-made-the-state.md`.

**Grep the ADR corpus for the proposed *mechanism*, not just the cited issue refs.** When the feature description names HOW to do something (a frontmatter flip, a new table, a polling cron, a config tier), grep `knowledge-base/engineering/architecture/decisions/` for the mechanism's keywords and read any hit's `## Decision` + `## Alternatives Considered` BEFORE accepting the framing or confirming a design with the operator. An issue is filed without knowledge of what an ADR decided; a mechanism in an ADR's rejected-alternatives table is explicitly-rejected, not unconsidered — re-scope to "did the ADR leave a gap this still addresses?". **Why:** #5087 — operator-confirmed frontmatter tiering matched the exact alternative ADR-053 (#5096) rejected the day before; caught only at deepen-plan. See `knowledge-base/project/learnings/2026-06-11-brainstorm-grep-adr-corpus-for-proposed-mechanism-not-just-issue-refs.md`. **Also verify any cited ADR *number* → mechanism mapping before threading it into a subagent/leader prompt** — a number carried from prior prose (e.g. "Anthropic-only = ADR-083") can be wrong (ADR-083 is the scoped strong-model consult; the model policy is ADR-053), and leaders will repeat the wrong citation as a given; `git grep "ADR-0NN" main` + read the citing text, and cross-check tree-wide before concluding an ADR is absent (a `git ls-files` glob miss ≠ non-existence). See `knowledge-base/project/learnings/2026-07-04-verify-adr-citation-numbers-before-threading-into-subagent-prompts.md`.

**When a governing ADR already contains the design, re-verify each *deferral trigger* against LIVE state — the "deferred/blocked" label is the most perishable part of an ADR.** A same-day ADR may record the full design AND label items deferred/blocked; trusting the label re-derives decided work or re-confirms a status that has since cleared. Read the deferral *rationale* and re-run the exact check it implies: `gh run list --workflow=<apply>.yml` if the reason is "pipeline RED"; `gh pr list --state all -L 200 --search "<N> in:body,title"` for a sibling that shipped an item ("Ref #N" merges leave the issue OPEN with the box unchecked); `gh issue view <blocker> --json state,title` to confirm the cited blocker is real and open; grep the IaC/source for the true cross-ref (a mis-cited blocker in prose is corrected by the code). Then the brainstorm's job is certify-and-scope, not explore-and-derive. **Why:** 2026-07-03 #5933 — ADR-082 (same-day) deferred Item 1 "blocked on #5887 (pipeline RED)", but #5887 was fixed, the apply was green, and Item 3 had already shipped via PR #5945; the blocker was mis-cited (#5887 is a closed CI fix; the real cutover is #5274). See `knowledge-base/project/learnings/2026-07-03-brainstorm-re-verify-adr-deferral-triggers-against-live-state.md`.

**Credential/auth/ToS features — probe the customer-facing-vs-operator-self-use framing split before accepting a blanket "prohibited."** A domain-leader (esp. CLO) PROHIBITED verdict is a verdict on ONE framing under ONE snapshot of vendor terms. Two cheap probes can invert it: (1) is there a narrower *actor/scope* (operator self-use, single-tenant, BYO-own-credential) that dissolves the fatal clause (credential *sharing*/*pooling*/*reselling* apply to customer-facing, not operator-self-use)? (2) are the cited terms *current*? Verify external-vendor commercial/ToS terms via live WebFetch of the official source dated to the present — terms drift and can flip within days. **Why:** 2026-06-02 #4825 — a triad PROHIBITED for customer-facing Claude-subscription login flipped to permitted-with-guardrails for operator self-use once the actor narrowed AND Anthropic's June-15-2026 Agent-SDK-credit policy was read live. See `knowledge-base/project/learnings/2026-06-02-brainstorm-framing-split-flips-tos-verdict-and-verify-vendor-terms-live.md`.

**Verify dependency-chain target states when the feature description cites cross-issue actions.** Extend the Pre-worktree premise probe above: if the feature description (or referenced parent issue body) names actions like `unblock #N`, `comment on #N to close`, `closes #N when this lands`, or `depends on #N closing`, run `gh issue view <N> --json state,closedByPullRequestsReferences` for each cited target. If the target is already CLOSED via a PR whose number is NOT in the current brainstorm's scope, the dependency chain has been satisfied through an independent path — record in the brainstorm doc's `## Session Errors` so PR-body authors don't add stale cross-issue actions. See `knowledge-base/project/learnings/workflow-patterns/2026-05-20-brainstorm-ladder-collapse-and-dependency-chain-staleness.md`.

**A soak-gated / "required-on-signal" tracker item is not scopeable until its trigger fires — and an issue-body obstacle is usually a property of the author's imagined approach, not the goal.** When the feature description is a multi-item tracker: (1) for any item gated on a soak/observation window ("if X stays non-zero after a one-week soak", "required-on-signal", "close only if zero residual"), verify the gating event's merge/clock date (`gh pr view <N> --json mergedAt`) — if the window has not elapsed, scope ONLY the independently-actionable sibling items and surface the gated one as "not yet actionable" via `AskUserQuestion`, rather than spinning up worktree+leaders for work whose trigger has not fired; (2) when an item's body asserts an obstacle ("needs a push-shaped payload", "expands blast radius"), grep the consuming helper's ACTUAL signature before accepting it — the obstacle is often specific to the heavyweight approach the author imagined and dissolves under a lighter one (e.g. `syncWorkspace` pulls live default-branch HEAD itself, so no synthetic push payload is needed). See `knowledge-base/project/learnings/2026-06-29-brainstorm-soak-gated-tracker-item-and-grep-helper-sig-before-accepting-obstacle.md`.

**A stale deferral's recorded REASON can be wrong while its VERDICT is right — re-derive the mechanism before reversing it.** Falsifying a deferral's stated rationale (the cited token IS in Doppler; the "unresolvable" id DOES resolve) does NOT establish that its verdict was wrong — the prior decider may have been right for a reason they never wrote down. Premise-probing correctly flags such an artifact as stale, and that is exactly what makes it dangerous: the probe's success manufactures confidence to reverse a correct decision. Before acting on the re-frame, re-derive the verdict's MECHANISM with the actual call (`terraform plan`, the real API request under the real token) — not the citation. Corollary: an id resolved via endpoint A is NOT evidence a Terraform `data` source can read it (the data source may hit endpoint B under a different scope), and a `data`-source failure is a whole-root outage on every future apply, not a local one. **Why:** #6285 — the deferral's two stated blockers were both false, yet its rejection of `data "sentry_team"` was still correct: the IaC token has no `team:read`, so the data source 403s at PLAN time and would wedge every `apply-sentry-infra` run. See `knowledge-base/project/learnings/2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md`.

**"Resource X is exhausted, so guard operation Y" — trace whether Y actually CONSUMES X at the moment it runs, before scoping the guard.** A replace/swap/rotate-shaped operation **frees its own unit before taking one** and is therefore net-zero on the resource it appears to exhaust — the guard belongs on the *additive* path, if anywhere (and there it is usually redundant, since an additive create fails cleanly with zero blast radius). Also check WHICH vendor error code the cited incident actually threw: an *exhaustion* code (account-wide quota, fixed by a vendor form) and an *availability* code (per-DC stock, fixed by not pinning a DC) are different counters with different fixes, and a guard on the wrong one returns green while the failure happens. "No headroom" is intuitively alarming and reliably mis-aimed. **Why:** #6453 — a `free_slots == 0` preflight would have failed **every** recreate for no reason (terraform `-replace` destroys first, freeing its slot, then creates), and the cited incident #6393 threw `resource_unavailable` (hel1 DC stock), not `resource_limit_exceeded` (the cap); the wrong model survived the issue author, the CPO, and the platform-strategist. See `knowledge-base/project/learnings/2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md`.

#### 1.1 Research (Context Gathering)

**Pre-research: check existing KB artifacts first.** Before spawning any agents, run one local check for prior brainstorms and specs matching the feature's topic keywords:

```bash
find knowledge-base/project/brainstorms knowledge-base/project/specs knowledge-base/project/learnings \
  -maxdepth 3 -type f -iname "*<keyword>*" 2>/dev/null | head -n 20
```

If prior artifacts exist, read them and frame the research agent prompts as "given these prior decisions, what's changed and what gaps remain?" rather than "research this topic cold." **Why:** In the 2026-04-17 BYOK usage dashboard brainstorm, the prior `2026-04-10-byok-cost-tracking-brainstorm.md` and `specs/feat-byok-cost-tracking/spec.md` had already decided scope; agents rediscovered them mid-session instead of building on them. See `knowledge-base/project/learnings/2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md`. Use `-type f` to avoid false positives from empty spec directories left by prior `worktree-manager.sh feature` runs that bailed before writing spec.md. **Run the `find` from inside the worktree** (after Phase 0/Phase 3 worktree creation) — the bare-repo root checkout can drift from `origin/main` and surface paths that don't exist at the worktree's revision, wasting research-agent prompt budget on summarize-a-missing-file instructions. **Same rule for `git ls-files`, `grep -r`, and any other pre-spawn premise-validation queries** whose result will be passed verbatim into a Phase 0.5 / Phase 1.1 subagent prompt — the bare root's index can lag main's HEAD, producing ghost-absent files that propagate into the subagent prompt as load-bearing false-negative assertions. See `knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md` and `knowledge-base/project/learnings/2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`.

**Write-mostly artifact diagnosis.** When the prior-art grep surfaces an existing ledger/queue/backlog/inventory that matches the claimed gap, check whether it has any closure markers (resolution status, linked closing issue, or `gh issue list --state closed -L 200 --search "<topic>"` hits). An artifact with zero closures over months is a falsifiable signal that automation producing *more entries* will compound the backlog, not the knowledge — reframe the brainstorm to ship the lifecycle/closure prereq first and let 60-day closure evidence decide whether the production loop is worth building. **Why:** 2026-05-12 #2723 tech-debt-tracker brainstorm — issue framed as "no persistent ledger" but `knowledge-base/project/learnings/technical-debt/` already had 11 entries with structured frontmatter and zero closures; the triad reframed to lifecycle prereq (#2723) + deferred scheduled scanner (#3650) with ALL-must-hold re-evaluation criteria, avoiding a CI-report-nobody-reads outcome. See `knowledge-base/project/learnings/2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md`. **For "make X legible/visible/surfaced" features specifically:** existence of the source is insufficient — measure its *production rate* (count rows past the ledger's header marker; `gh pr list --search "head:<branch-shape>" --state all -L 200`). A source that exists but has produced ~0 entries means the display surface renders empty; the real prereq is fixing the *producer*, not building the viewer. AND when copy says "*your* X got smarter/better", grep the producer for tenant scope (`workspace_id`, `WHERE tenant`) — if it only writes global/shared artifacts, possessive per-tenant framing is a deceptive-implication risk; reframe to product-level. **Why:** 2026-07-06 #6039 — promotion-log had 0 rows, 0 `self-healing/auto-*` PRs ever, and improvement is global-harness-only; re-scoped to an operator dogfood + deferred the founder surface (#6102). See `knowledge-base/project/learnings/2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface.md`.

**An "advisory-first, promote later per the <X> precedent" framing is a claim to MEASURE before it sets the new gate's posture.** When an issue cites a prior gate as calibration precedent, verify the precedent's promotion actually happened — the author is citing the *intent* they remember, not the *outcome*: (1) `grep -rl "<scanner>" .github/workflows/` — if it returns nothing, the "precedent" is a skill script, not a CI gate, and there was never an advisory stream to promote; (2) `gh issue view <calibration-issue> --json state,createdAt,comments` — compare age against the stated window and count ORGANIC findings (a window open past its deadline with only ship-day comments + a triage bot produced nothing); (3) ask whether ANY advisory gate in this repo was ever promoted to blocking — if zero-for-N, born-blocking is the only mechanism with a track record, and "advisory now, blocking later" is the option that reliably ships a warning stream with no reader and no expiry. A gate that cannot be scoped precisely enough to block is evidence the *detector* is wrong, not evidence it needs a calibration window. **Why:** #6517 — `tier1-scan.ts` is in zero workflows and calibration issue #4270 sat OPEN at 56 days against a stated 2-week window with 0 organic findings, while the arm that did ship blocking (#4646) was born blocking. See `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md`.

**Also check sibling/closed issues for prior framings of the same mechanism.** When the feature_description references `#N` with a parent (`Parent: #M` in the body or an umbrella issue), read the parent's child list AND run `gh issue list --state all -L 200 --search "<core-mechanism-keywords>"` to surface deferred or closed prior framings. **Why:** 2026-05-11 #2720 brainstorm — the issue was a re-framing of #421 (deferred Layer 2 of self-healing-workflow); without this check, the brainstorm would have produced a parallel spec orphaning #421. See `knowledge-base/project/learnings/2026-05-11-brainstorm-parallel-domain-and-research-fan-out-and-duplicate-issue-discovery.md`. When the inciting event is a vendor pricing/model/terms change, additionally grep OPEN issues for deferred work whose re-evaluation criteria name that event class (`gh issue list --state open -L 200 --search "deferred <pricing|model|vendor-keyword>"`) — deferred issues encode prior leader consensus plus re-open criteria, and the brainstorm's job may be certifying the trigger fired, not re-deriving the decision (2026-06-10: #3791's "pricing change" trigger sat dormant through the Fable 5 release). When the operator explicitly **overturns** a recorded deferral/validator verdict instead of certifying its trigger: state in the brainstorm which conditions are satisfied vs. overridden and why, comment the partial override on the deferred issue (keep it OPEN for the un-overridden remainder), and inherit its captured "if/when built" decisions verbatim into the new spec — never silently fork (2026-06-10: #5103 overrode #4788 condition 1 only; K6 decisions inherited).

**External-framework/article brainstorms — audit existing primitives before framing greenfield.** When the request is "apply the technique(s) from this paper/article/framework to Soleur" (as opposed to a prior Soleur artifact), the first move is an existing-primitive audit, NOT a from-scratch design. First verify the source is real (WebSearch/WebFetch the paper + repo — fabricated frameworks are a live failure mode), then translate each concept in the source into Soleur's current primitive and its automation level, and prompt the research/leader agents to "MAP THE CURRENT STATE and find the ONE open gap — do not propose from scratch." The productive deliverable is a stage→primitive→automation→gap table that scopes the smallest zero-risk increment closing the open stage. **Why:** 2026-07-05 self-improving-harness brainstorm (#6037) — Soleur already implemented ~70% of Self-Harness/HarnessX (`cron-compound-promote`, `rule-metrics-aggregate`, `eval-gate`/ADR-069, #397 self-healing Layer 2, #5768 harness-L3) before the article existed; greenfield framing would have re-specced shipped infra. See `knowledge-base/project/learnings/2026-07-05-external-framework-brainstorm-audit-existing-primitives-before-greenfield.md`.

Run these agents **in parallel** to gather context before dialogue. **Spawn domain leaders (Phase 0.5) and research agents (Phase 1.1) in one parallel batch** via `run_in_background: true` — they're independent. While agents run, use the wait time for local prior-art file checks and parent/sibling issue inspection rather than blocking on a wakeup. **Why:** 2026-05-11 #2720 brainstorm — 4 leaders + 2 research agents in one batch returned in 60-180s vs. ~10 min sequenced.

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, similar features, CLAUDE.md guidance
- **Learnings:** documented solutions in `knowledge-base/project/learnings/` -- past gotchas, patterns, lessons learned that might inform WHAT to build
- **Rotate-everywhere features (DSN swaps, key rotations, vendor migrations):** the repo-research-analyst prompt MUST explicitly include "grep `.github/workflows/scheduled-*.yml` for credential-triple consumers — runtime config inventory is reliably ~50% of true blast radius." Operators write feature descriptions from the runtime-rotation mental model; scheduled CI workflows typically hold a separate credential class (cron-checkin keys, write-only beacons) invisible from that vantage. See `knowledge-base/project/learnings/2026-05-16-repo-research-must-inventory-scheduled-ci-workflows-for-secret-sweeps.md`.

**Verifying "is X mounted/wired/enabled?" claims.** When a research agent (or your own reasoning) asserts that a component is not present, not mounted, or not wired up, verify by grepping for the **specific consuming symbol** (a variable, hook, state field, or imported component name) rather than relying on absence of a generic phrase. Absence of the feature name in search results is not evidence of absence in code. **Same applies to file-existence claims:** when a subagent reports "file X does not exist on disk," independently verify with `ls <absolute-worktree-path>` from the orchestrator before propagating into brainstorm artifacts — subagent CWD or path-resolution can produce false negatives, particularly across worktree vs. bare-repo paths. **Why:** In the 2026-04-17 session, the Explore agent reported the chat cost badge was "not confirmed to be rendered" because it grepped "cost badge" (no code match); the badge was in fact mounted via `usageData.totalCostUsd` in `chat-surface.tsx`, which a targeted grep for the state identifier would have caught. **Why (file-existence):** 2026-05-10 brainstorm of #2719 — CLO subagent reported `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` missing; compound-time verification found it exists, the false negative had already been written into the brainstorm document and required a correcting edit. **Same applies to "reuse the X-query code in file Y" claims:** grep file Y for the *specific external-API symbol the new code needs* (the read endpoint, the auth-token var) before accepting the reuse premise — a file that WRITES to a vendor (POST heartbeat, webhook, ingest DSN) is NOT evidence it can READ from that vendor; write-auth and read-auth are distinct credential/env surfaces. **Why (reuse-direction):** 2026-05-30 #4654 — issue body said "reuse the Sentry-query code in `cron-inngest-cron-watchdog.ts`", but the watchdog reads Inngest `/v1/functions` and only POSTs Sentry heartbeats; the Sentry check-in *read* was net-new and needed an undefined auth token. **Same applies to your own capability claims:** before bounding the brainstorm's options with "tool X is GUI-only / can't do Y", grep/read the source first or phrase it as a question (hard rule `hr-verify-repo-capability-claim-before-assert`).

**Verifying "this is a regression of #N" claims.** When the feature description (or your framing) attributes a post-deploy symptom to a recently-merged PR, do NOT accept the attribution until the symptom's trigger path is traced end-to-end: grep the literal rendered string → locate the render condition → identify the state/event that triggers it → cross-check that trigger path against the PR's file diff. If the PR did not modify any file on that path, the symptom is NOT a regression of that PR — it is a distinct latent bug or an adjacent uncovered code path. See `knowledge-base/project/learnings/2026-04-23-verify-trigger-path-before-attributing-regression.md`.

**Verifying referenced PR/issue state.** When the feature description references an adjacent PR or issue (e.g., "PR #N adds X" / "this is the durable fix for #N"), verify the referenced state with `gh pr view <N> --json state,mergedAt` + a grep for the specific symbol the PR is supposed to have introduced (e.g., `git grep -l "<symbol>" main`) BEFORE accepting any sequencing claim from the issue body or weaving it into domain-leader prompts. Issue bodies are written at one point in time and aren't updated when adjacent PRs land or stall. A "PR #N is merged" claim that is false will produce internally-coherent leader recommendations premised on a wrong factual floor (e.g., a CPO "park this" recommendation premised on a bridge fix that hasn't actually shipped). For long-running brainstorms (>30 min between session-start verification and option presentation), re-run the same `gh pr view <N> --json state,mergedAt` check immediately before presenting architecture options whose pros/cons turn on prereq PR state — parallel sessions can merge a prereq mid-brainstorm and dissolve option premises (2026-05-10 #3509 brainstorm: prereqs #3495 and #3508 both merged during the session, dissolving two of three presented options). See `knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md`.

**Enumerating umbrella child PRs before spawning leaders.** When the feature description references a GitHub umbrella issue (`#N`) AND that issue is OPEN AND its body mentions sub-PRs by letter ("PR-A", "PR-B", "Stage 1", "Phase 1") OR enumerates increments/slices, run `gh pr list --state all --search "<branch-slug-from-issue-body>" --json number,state,title,mergedAt --limit 20` BEFORE spawning Phase 0.5 leaders. The output is the source of truth for "what already shipped" — pass the merged-PRs list into every domain-leader prompt's context section so leader recommendations are not premised on stale decompositions. `tasks.md` / `spec.md` checklist files lag merged work (the in-flight PR may have closed boxes that never got back-checked into main, and umbrella issue bodies are written-once at decomposition time). Distinct from the adjacent `gh pr view <N>` check above (single named PR) and the cited-flag-symbol check below (named architectural mechanism) — this targets the multi-stage decomposition pattern specifically. **Why:** 2026-05-15 #3244 brainstorm — CTO leader read stale `tasks.md` showing §1.5-1.8 unchecked and recommended "finish PR-B"; PR-B (#3395) had merged 9 days earlier on the sibling `feat-agent-runtime-platform-pr-b` branch. See `knowledge-base/project/learnings/2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md`.

**Verifying "approach 1 vs approach 2" claims.** When the feature description (or the referenced issue body) proposes named architectural approaches AND cites a parent PR or recent commit, grep `main` for the symbol that approach 1 would introduce (a function name, callback hook, or call site mentioned in the issue body) BEFORE Phase 0.5 leader spawn. Presence-on-main is a strong staleness signal — the brainstorm should pivot to *audit residual risk* not *design the fix*. Five seconds at Phase 1.1 saves a multi-leader spawn at Phase 2. This is sharper than the adjacent `gh pr view` check above because an *adjacent* PR (not the cited one) commonly implements the approach. See `knowledge-base/project/learnings/2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md`.

**Treating `claude[bot]` / `bot-fix/attempted` comments as read-only context, not recommendations.** When the issue carries a `bot-fix/attempted` label or `claude[bot]` comment trail, the bot's chosen fix shape optimized for the `fix-issue` skill's single-file constraint — not for brand-survival or user-impact threshold. Read what the bot tried for context, then re-derive the fix shape from leader consensus (Phase 0.5). The bot's "needs multi-file" bail-out is a handoff signal, never an endorsement of the partial shape it attempted. See `knowledge-base/project/learnings/2026-05-07-bot-fix-single-file-constraint-not-a-signal-for-brainstorm-fix-shape.md`.

**Cross-checking leader infra/substrate claims against repo-research.** When a domain leader (CTO, CPO, etc.) returns a recommendation that names a specific substrate ("use Vercel cron", "Edge Function + cron poll", "the existing X queue") with phrasing like "already wired" / "already running" / "identical auth model", verify the claim with a targeted grep BEFORE treating it as authoritative. Read the parallel repo-research report first — leader agents reason strategically and may prescribe substrates that don't exist in *this* codebase. If grep returns zero matches for the substrate's diagnostic symbol (`cron` config, `setInterval` site, Edge Function directory), treat the leader recommendation as a NEW substrate proposal (with the ops cost that entails), not a "use what's there" recommendation. **Why:** 2026-05-12 D-DSAR-art15 brainstorm — CTO recommended "Vercel cron + serverless" with "already running" phrasing; repo-research confirmed no Vercel cron and no Edge Functions directory were wired (only `pg_cron` + one `setInterval` site). Catching this at brainstorm produced three candidate substrates in Open Questions; missing it would have produced a spec premised on infra that doesn't exist. See `knowledge-base/project/learnings/2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md`.

**Auditing new online write surfaces against existing detection primitives.** When a brainstormed proposal adds a new write surface (HTTP route, callback, CLI tool, scheduled writer) to any Doppler config, GH Actions secret, Supabase table, repo-tracked file, or DNS record, grep `.github/workflows/scheduled-*.yml` + `.claude/hooks/` + `plugins/soleur/skills/*/scripts/` for existing detection primitives (cron, hook, validator, audit) that READ from that same surface. If any detector reads from the proposed write target, the detector's invariant silently regresses — the detector now compares attacker-writable inputs against themselves (`x == x` tautology). Either move the detector's "expected" side out-of-band (signed file in the repo, separate config the write path cannot reach) in the same PR, or scope-cut to avoid the online write. Surface this BEFORE Phase 2 approach selection — once architecture options are anchored on the online-write substrate, the scope cut becomes a re-spec. **Why:** 2026-05-20 #4115 brainstorm — issue body proposed an HMAC-gated callback writing 5 GitHub-App credentials to Doppler `prd`; `scheduled-github-app-drift-guard.yml` (#3187) reads those same credentials to assert App-identity immutability. Adding the write path would have silenced the drift-guard by making both sides of its compare attacker-rewritable. CTO surfaced this at Phase 0.5; the response was a scope cut to manifest-only. See `knowledge-base/project/learnings/2026-05-20-online-write-on-source-of-truth-breaks-detection-invariant.md`.

**Verifying a cited infra/domain-auth requirement against the IaC root before sizing it as an in-feature checklist item.** When the issue body lists an infra prerequisite (SPF/DKIM/DMARC/MX for domain X, a Cloudflare zone, a Terraform-managed resource) as one checkbox among many, grep the IaC root (`apps/web-platform/infra/*.tf`) for the domain/zone BEFORE accepting it as an in-feature task. If the zone is absent from IaC, it is a **blocking zone-onboarding prerequisite** (its own onboarding cost + token-reachability question per `hr-fresh-host-provisioning-reachable-from-terraform-apply`), not a checkbox — file it as a dependency and sequence it first. A capability-existence claim tends to *understate* what exists (grep the primitive symbol); an infra-readiness claim tends to *overstate* readiness by listing a not-yet-provisioned zone (grep the IaC root) — opposite failure directions, different probes. "Inbound already works at ops@domain" does NOT imply the zone is IaC-managed. **Why:** 2026-06-15 #5325 brainstorm — issue listed "SPF/DKIM/DMARC for jikigai.com" as a checklist item, but `infra/dns.tf` is single-zone (soleur.ai); jikigai.com was in zero Terraform, making it a blocking prereq. See `knowledge-base/project/learnings/2026-06-15-brainstorm-verify-cited-infra-prereq-against-iac-root.md`.

**A "connect X / set up X" CTA is a capability claim — grep the ingestion + record-attribution path before sizing it.** When the feature description adds an affordance presuming an underlying integration ("CTA to connect the founder's Gmail/Proton", "set up your email", "link your calendar"), grep the data-ingestion/config path BEFORE folding it into scope: the webhook/receive route, the **env var or column that attributes records to a user/workspace**, and the IaC for the address/credential. Single-tenant infra constants (a `*_OWNER_USER_ID` env, one provisioned address) routinely masquerade as multi-tenant features in a request. If attribution is a hardcoded constant, the CTA has nothing real to link to — decouple: ship the presentation surface now, file the connection capability as its own brainstorm (CLO+Ops+CTO for mailbox/OAuth scope). Run the probe DURING dialogue, not after. **Why:** 2026-06-18 #5512 — "connect email (Google/Proton)" CTA presumed multi-tenant ingestion, but the inbox is single-tenant (fixed operator `ops@` address + `EMAIL_TRIAGE_OWNER_USER_ID`, `email-on-received.ts:310`); decoupled to #5527. See `knowledge-base/project/learnings/2026-06-18-brainstorm-verify-cta-presumed-capability-before-scoping.md`.

**Reconciling fast-returning leader recommendations with later-arriving research findings.** Phase 0.5 leaders typically return in 20–40 s; learnings + repo research can take 2–5× longer. If a research agent surfaces evidence that contradicts a leader's recommendation (e.g., the leader recommends retrofitting `/goal` into `test-fix-loop`, but research surfaces that `test-fix-loop` already uses deterministic exit-code gates that `/goal` would duplicate at higher cost), name the contradiction explicitly and either re-prompt the contradicted leader with the research findings OR re-scope the approach BEFORE Phase 1.2 dialogue begins. "Weave each leader's assessment alongside research" is too soft when the two disagree; the leader-shaped framing wins by default unless the brainstorm parent forces a reconciliation pass. **Why:** 2026-05-15 `/goal`-primitive brainstorm — CTO at t=35s recommended `test-fix-loop` as pilot retrofit candidate; learnings-researcher at t=124s and repo-research at t=215s independently showed the existing exit-code gate + Soleur's 316-line ralph-loop Stop hook made the entire retrofit premise obsolete. Without explicit reconciliation, the brainstorm would have proposed a worse approach the leader had already committed prose to. See `knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md`.

**Confirming the target-state premise with the operator BEFORE the first leader spawn (architecture issues).** For an architecture brainstorm, the *target end-state* is the premise every Phase 0.5 leader reasons from. When the issue does not state it, do NOT infer it from current runtime state and spawn leaders — a runtime snapshot (e.g. "web-2 pinned at LB weight 0", "single-active by design") is often a temporary bootstrap condition, not the design intent, and leaders will build internally-coherent recommendations on whatever floor you give them. Surface the inferred target-state and confirm it via one `AskUserQuestion` BEFORE the first leader spawn; a wrong floor costs a whole parallel round (and can fully reverse the verdict). **Why:** 2026-07-07 #6178 inngest-host brainstorm — the CPO/CLO/CTO+platform-strategist triad recommended "in-place decouple + close as YAGNI" premised on inferred single-active; the operator's real target (active-active-N web) reversed it to mandatory extraction. See `knowledge-base/project/learnings/2026-07-07-brainstorm-confirm-target-state-before-leader-spawn.md`.

**Verifying issue-body architectural constraints against the plugin-wide rule corpus.** When the feature description quotes an architectural constraint from the issue body (e.g., "no stdlib Python CLI", "no X allowed in skills"), verify it against `plugins/soleur/AGENTS.md` and a spot-check of `plugins/soleur/skills/**/scripts/` BEFORE letting it bound the option space at Phase 2. Issue bodies are written at one point in time and drift from the plugin's actual practice; uncritically accepting a constraint that overstates the rule cuts off viable architectures and biases toward heavier alternatives. See `knowledge-base/project/learnings/2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound.md` Pattern 1.

**Verifying cited-plan-doc code claims against main, not just issue bodies.** When the feature description cites a prior plan/spec/brainstorm doc, treat its concrete code claims (component *names*, route *paths*, exact *HTTP-status* behavior) as point-in-time prose that drifts from code — NOT as a more authoritative source than the code it describes. Grep `main` for the specific symbol (the component name, the route file + the literal status code) BEFORE letting the claim bound Phase 2. A doc authored "against live prod data" earns trust on the DB values it actually measured, but its code-shape claims are often paraphrased or misremembered. #4712: the plan named a `RepoConnectionCard` that exists nowhere in code (real surface = `ProjectSetupCard`) and asserted `/api/kb/tree` 409s on `repo_status='error'` (it 404s/503s; the 409s are in `/api/kb/sync`) — both caught by repo-research grep before they shaped the spec. See `knowledge-base/project/learnings/2026-06-01-brainstorm-verify-cited-plan-doc-claims-not-just-issue-body.md`.

**Verifying issue-body option enumerations against library API surface.** When the issue body names approaches "Option A / B / C" with one marked Recommended, grep the relevant library's `.d.ts` / framework types / MCP schemas for additional degrees of freedom (extra config primitives, hooks, formatters, serializers, middleware) BEFORE accepting the listed enumeration. The "Recommended" tag is the reviewer's vote against the alternatives they considered, not a vote against alternatives they missed; inventory grep + API-surface grep can surface a 4th option that dominates the 3 listed. Also re-run any inventory count cited in the issue body — drift between issue creation and brainstorm is common (e.g., 27 → 10 in 6 hours when a parallel PR absorbed sites). See `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md`.

**Verifying cited flag/symbol against main before spawning leaders.** When the issue body cites a capitalized symbol (`FLAG_*`, `ENABLE_*`, `USE_*`, `FEATURE_*`, `*_ENABLED`) or an uppercase camel-case feature name as the gating mechanism, grep `main` for the symbol and read the first ~20 lines of each match for a retirement comment (`retire|removed|deprecated|sunset`) BEFORE spawning leaders. The retirement-comment-in-owning-module is a high-signal failure mode for follow-through and Stage-N issues — multi-stage plans create child issues that describe a gating mechanism the parent assumed, then a subsequent stage or out-of-band PR retires it while the child issue's body is never updated. A 30-second grep at Phase 1.1 saves a multi-leader spawn premised on the wrong scope (the catch otherwise happens at Phase 0.5 leader convergence, costing 3-5 min of parallel agent compute and forcing every leader to mid-assessment reframe). Distinct from the `gh pr view` check (adjacent-PR claims) and the approach-hook check (named architectural approaches) above — this targets cited *symbols* still referenced by name in the issue's own body. See `knowledge-base/project/learnings/2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md`.

**Verifying whether a referenced artifact exists but is only half-wired (capture layer shipped, enforcement unwired).** When an issue frames work as "build X" AND a sibling PR has recently merged, grep the worktree for the cited table/migration/resolver/symbol BEFORE spawning leaders — and if it exists, read its body to find which *layer* is missing. A data/capture layer and its enforcement/gating layer are separable; a prior PR commonly ships the easy reviewable half (table + route + display) while deferring the runtime-behavior half (the gate that actually changes behavior). "Build X" is a claim about desired end state, not about what's on main. The real gap is then narrower and sharper than the issue's greenfield framing — leaders premised on "design from scratch" waste cycles re-deriving shipped code. Distinct from the `gh pr view` state check (whether referenced work is stale) — this targets *the referenced artifact existing but only partially wired*. See `knowledge-base/project/learnings/2026-05-29-brainstorm-sibling-pr-shipped-capture-layer-enforcement-gap.md`.

**Verifying PIR-follow-up "build detection / build a probe" framings against the observability layer + sibling-PR merge dates.** A PIR follow-up is typically authored while its author is focused on the *recovery* PR in flight, and discounts *detection* work that sibling PRs shipped between the incident and the issue-filing date. Before accepting a "detection still depends on a user noticing / add a scheduled probe" framing: (1) grep the observability layer for the proposed mechanism — `cron-*.ts` Inngest functions AND `infra/sentry/*.tf` — not just app code; the probe may already exist and the only gap is the *alert rule* on its events (`hr-no-dashboard-eyeball-pull-data-yourself`); (2) diff the sibling-PR `mergedAt` against the issue `createdAt` (`gh pr view <N> --json mergedAt` vs `gh issue view <M> --json createdAt`) — arms that merged BEFORE the issue was filed invalidate an "X doesn't exist" premise even on a brand-new issue; (3) verify the row/event shape the proposed condition produces, to confirm whether an existing blanket check already covers it. **Why:** 2026-06-03 #4882 — issue proposed building a KB-sync-stale detection probe; `cron-workspace-sync-health.ts` arms #4712/#4717 had shipped it two days prior, and the only real gap was a missing `sentry_issue_alert`. See `knowledge-base/project/learnings/2026-06-03-brainstorm-grep-observability-layer-before-greenfield-detection-framing.md`.

**Verifying whether the target table is append-only before accepting an "edit the row" framing.** When the feature proposes mutating an existing row (rotate a token, reset an expiry, swap a value) on a table that stores audit/PII/lineage data, grep for a `*_no_mutate` trigger, WORM comment, or "immutable once set" guard BEFORE accepting the in-place-edit framing: `git grep -nE "no_mutate|is immutable|immutable" -- '<migration-glob>'`. If the column is immutable, the operator's "edit the record" mental model is incompatible with the schema — the aligned pattern is revoke-old-row + insert-new-row in one SECURITY DEFINER transaction (the old token/link dies because accept/lookup already reject revoked rows; atomic by construction; no trigger change). Catching this at Phase 1.1 turns a doomed in-place RPC into the correct supersede pattern. **Why:** 2026-05-29 #4636 resend-invite — `workspace_invitations_no_mutate` (075:93) makes `token_hash`/`expires_at` immutable; CTO+CLO surfaced it, verified by direct migration grep. See `knowledge-base/project/learnings/2026-05-29-brainstorm-grep-worm-trigger-before-accepting-in-place-edit-framing.md`.

**Verifying data-source granularity for per-X aggregation claims.** When the issue body proposes a mechanism keyed on "read `<file>` for per-X counts" (per-user, per-tenant, per-rule, per-learning, per-skill), the existence probe (`ls path`) is necessary but insufficient — probe the file's actual entity granularity via `git show main:<path> | jq 'keys, (.rules // .entries // [])[0]'` BEFORE accepting the proposed mechanism. A file present on `main` can still be the wrong substrate: e.g., `knowledge-base/project/rule-metrics.json`'s `.rules[].id` are AGENTS.md rule slugs (`cm-challenge-reasoning-instead-of`), not learning file paths — so "read rule-metrics.json for per-learning hit counts" (#4042 issue body) is mechanically impossible regardless of file existence. 10 seconds at Phase 1.1 saves a full Phase 0.5 leader fan-out on a wrong-premise feature. Distinct from the file-existence check, the cited-flag-symbol check, and the architectural-constraint-against-rule-corpus check above. See `knowledge-base/project/learnings/2026-05-19-brainstorm-pre-committed-ladder-and-data-source-granularity-check.md` Pattern 1.

**Verifying issue-body mechanical disambiguators against runtime state before leader spawn.** When the issue body enumerates a probe (`curl`, `gh api`, DSN-substring read, config lookup) whose result would narrow multiple speculative remediation tracks to one, run it BEFORE Phase 0.5 leader spawn. Cost: seconds. Benefit: leader prompts become single-track and correctly-thresholded instead of speculating across N branches of which one is real. Distinct from the approach-hook check (whether named work is still relevant) and the cited-flag check (whether named gates still exist) — this answers *which of N speculative branches is real* when the issue body itself names how to find out. **Why:** 2026-05-15 #3861 brainstorm — issue enumerated three Sentry-residency remediation tracks; a 5-second DSN cluster-substring read from Doppler `prd` (`o<id>.ingest.de.sentry.io`) collapsed the three speculative tracks to one and softened the brand-survival framing from "Article 33 statutory clock" to "misleading §5(2) accountability evidence" before the CPO+CLO+CTO triad spawn. See `knowledge-base/project/learnings/2026-05-15-brainstorm-probe-first-before-leader-spawn.md`.

**A cumulative counter cited as a loop/churn signal is meaningless without its window — read `stats_reset` first; and a "residual" is unmeasurable while the dominant source it's residual to is still in the window.** When an issue cites `pg_stat_statements` call counts (or any cumulative metric — Sentry event totals, cron run tallies, WAL `calls`) as evidence of a runaway loop or hot path, query the counter's reset timestamp (`SELECT stats_reset FROM pg_stat_statements_info`) and divide by the window length AND the active-user count before accepting the framing — a "high" number is usually a long window, not a loop. Separately, when the issue is a *residual* of a just-landed fix ("the second-largest source after PR #N"), cumulative stats still show the fixed source dominating until the counter is reset, so the true residual share is unmeasurable until you reset + soak — the brainstorm's deliverable is often "reset and re-measure," not "design the optimization." **Why:** #5739 — 1,586 `recovery_token` UPDATEs read as a loop but were ~29/day over a 55-day window (no loop); the auth-WAL "residual" couldn't be sized until `pg_stat_statements` was reset post-#5736. See `knowledge-base/project/learnings/2026-06-30-pgss-window-and-reset-before-measuring-residual.md`.

**Verifying live-vs-paused state when the framing is "restore the paused X / unblock the held-back Y."** "Paused" and "needs containment" are independent axes — an issue author writing from the in-flight-PR mental model often frames an adjacent uncontained-but-LIVE actor as "future work" while the thing they just paused feels like "the dangerous thing." Before accepting the framing, verify every named actor against the runtime pause/defer registry (the defer-set / manifest), NOT the issue prose: grep the defer set + grep each "needs-a-boundary-before-it-runs" actor for its pause guard + confirm it's registered/live. If an actor named as future-work is already running, the work is *containment of a live exposure*, not *unblock of paused work* — which flips the brand-survival threshold and the sequencing options. **Why:** 2026-06-09 #5046 — issue titled "restore the paused crons" framed 4 `spawn("bash")` crons as future firewall work; they had no `deferIfTier2Cron` guard in `cron-manifest.ts` and were running live/uncontained, while the 11 "paused" crons were the safe population. See `knowledge-base/project/learnings/2026-06-09-restore-paused-framing-can-invert-risk-ordering.md`.

**Tier 2 cannibalization lens for competitive-audit umbrella candidates.** When the feature description is a single candidate from a competitive-audit umbrella's Tier 2 list, list the umbrella's explicit reject decisions, count how many sibling candidates already shipped, and ask "if we ship N more, do we reconstruct the rejected outcome?" If yes, the bar for this candidate is higher than its own merits — surface the cumulative count in the Domain Assessments so reviewers see the pattern. See `knowledge-base/project/learnings/2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound.md` Pattern 3.

**Audit-direction vs. guidance-direction split for community-skill imports.** When the feature description cites a community Claude Code skill repo (`alirezarezvani/`, `forrestchang/`, etc.) and proposes importing principles or rules, separate the **guidance direction** (tell the LLM to follow the rules — surface = system prompt / AGENTS.md) from the **audit direction** (check code against the rules — surface = review agents / `/soleur:review`). They are orthogonal: prior-art may have answered one direction but leave the other partially covered. Before sizing, grep `plugins/soleur/agents/engineering/review/` for the imported principle keywords and score row-by-row coverage in existing agent bodies (especially `code-simplicity-reviewer`). When ≥half the audit checklist already exists, default to extending the agent's output sections — not a new skill / agent / scripts. See `knowledge-base/project/learnings/2026-05-15-brainstorm-audit-vs-guidance-direction-reframe.md`.

**Verifying register/ledger citations against canonical content.** When the framing cites a markdown-table row in a register (`Article 30 row N`, `ADR-NNN`, roadmap milestone, tech-debt entry), grep the register FILE for the cited subject — not just the row identifier. The row may exist with different scope than the framing assumed. Concretely: `git grep -n "<cited-subject-keyword>" knowledge-base/legal/ knowledge-base/engineering/architecture/decisions/ knowledge-base/project/roadmap.md` and read each hit's surrounding context BEFORE leader spawn. Row-identifier paraphrase (`ADR-031 says X`) is a low-signal claim; subject grep against the register is high-signal. See `knowledge-base/project/learnings/2026-05-16-brainstorm-verify-register-citations-and-adjacent-silent-failures.md`.

**Reading the governing ADR's Alternatives-Considered before proposing to reverse/extend its data-model decision.** When the brainstorm would reverse or extend a decision recorded in an ADR, read that ADR's `## Alternatives Considered` table VERBATIM before authoring approaches — do not treat the ADR's chosen-vs-rejected pair as the whole option space. The rejected alternatives encode the decider's *reason*; the winning new option is often a third one the ADR never enumerated that dismantles that exact rejection reason. #4581: ADR-043 listed only "per-org segments (rejected: O(orgs) explosion)" vs "single shared segment (chosen)"; the un-enumerated "per-feature segment" (O(features)) resolved the explosion concern AND gave the missing per-(feature,org) granularity. See `knowledge-base/project/learnings/2026-05-29-brainstorm-read-adr-alternatives-considered-before-proposing-reversal.md`.

**Sibling-call discovery via stale narrative-comment canaries.** When the framing cites a single call site for a helper, helper sweep, or migration target, grep the codebase for stale narrative markers BEFORE accepting the citation as authoritative: `git grep -nE '(Migrated|migrated|completed|deferred|pending|TODO) in PR-[A-Z0-9]'`. Stale `Migrated in PR-X` / `pending PR-Y` comments on sibling call sites are higher-signal canaries than the call site itself — the comment IS the bug report, written by the prior PR's author as documentation of incomplete work. Spawning leaders without this sweep produces scope estimates that miss the surrounding canary work. See same learning file.

**Cross-umbrella PR-X label disambiguation.** When the feature description references `PR-A/B/C/D` Greek-letter labels, two parallel umbrellas can re-use the same letters with different meanings — disambiguate BEFORE leader spawn: `gh issue list --search "PR-X in:body" --state all -L 200 --json number,title,body | jq -r '.[] | "\(.number): \(.title)"'`. If multiple umbrellas surface, the framing's `PR-X` is ambiguous until tied to an umbrella tracker number. Leaders spawned with ambiguous PR-X references generate cross-umbrella confusion that costs minutes-to-hours of mid-assessment reframe. See same learning file.

**User-incident-class scope boundary for data-residency PRs.** When the brainstorm scope is data-residency, residency-of-this-data-stream framings can leave adjacent UI silent-failure modes out-of-scope by code-area taxonomy ("that's the consumer, not the producer"). UI silent-failure modes (`.catch(() => {})`, `.catch(noop)`, `void` on a promise) in the user-flow consuming residency-protected data manifest IDENTICALLY to a botched residency migration from the operator's perspective — the data the operator expects to see is missing, with no error surfaced. Scope them INSIDE the residency PR by user-incident class, not by code-area taxonomy. Grep before leader spawn: `git grep -nE '\.catch\(\(?\)? =>\s*\{?\s*\}?\)|\.catch\(noop\)|void\s+\w+\(\)' <consumption-path>`. See same learning file.

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

**Decouple a capability-build from time-sensitive content.** When a content/positioning brainstorm rides a decaying news window (a viral essay response, a launch-day reaction) AND the operator wants to "close the capability gaps first so we can claim full support," offer a *decouple* approach as a first-class option: ship the honest-hedge content now for the window, and track the gap-closing build as a follow-up issue that unlocks a stronger v2 claim on completion. Do NOT let the slower build block the timely content by default — build-first commonly overruns the very window that justifies the content. See `knowledge-base/project/learnings/2026-06-12-brainstorm-verify-capability-claims-against-code-and-decouple-build-from-news-window.md`.

**Budget checkpoint.** The Budget checkpoint fires when the operator names a new skill or proposes editing a `description:` line in any approach option (operator self-detects on naming, not pre-emptively). When fired, run the SKILL.md description word-budget measurement one-liner (Node form, see `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` **Measurement one-liner** section) before authoring approach proposals. If headroom is < 10 words against the 1800-word cumulative cap, each approach option MUST include a sibling-trim sub-plan that frees at least the required number of words. Approach options without a sibling-trim sub-plan are invalid and must be rewritten or dropped before Phase 2 closes. Surface the headroom number as a first-class constraint in the approach comparison table.

### Phase 2.5: Productize Checkpoint

When proposing an action plan, ask: is the inciting work pattern likely to recur (scheduled workflow output, weekly review cadence, batch-triggered task, recurring competitive-intel finding)? If yes, record a `Productize Candidate: <skill-name suggestion>` entry in the brainstorm's Key Decisions block; do NOT pivot the current brainstorm. The candidate becomes a follow-up issue (filed at brainstorm-end via the existing deferred-item issue-creation step), not a brainstorm scope change. A recurring-work plan that produces issues but no reusable artifact has done half the work.

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
   ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh feature <name>
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
   bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh draft-pr
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

### Phase 3.55: Visual Design (if feature has UI surfaces)

**Trigger.** Run this phase iff the brainstorm scope touches a UI surface per the shared term list (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`): pages, components, modals, banners, nav/layout, flows, email templates. A scope with **no** UI surface (pure infra/CI/legal/orchestration) genuinely skips — that is the trigger boundary, not a silent skip. For a UI-surface feature this phase has exactly **two** permitted terminal outcomes: a committed `.pen` artifact, or a **hard-block**. "Skipped" is NOT a permitted outcome (`wg-ui-feature-requires-pen-wireframe`).

**If UI surfaces exist**, spawn the ux-design-lead agent via the **Agent tool** to create wireframes in `.pen` files. The agent owns the output path convention (`knowledge-base/product/design/{domain}/`) — do NOT supply output paths in the spawn prompt.

**Agent prompt construction:** Build the prompt from brainstorm decisions:

1. List every UI surface from Key Decisions (pages, modals, banners, email templates)
2. Include design system context: existing component patterns, color tokens, layout conventions discovered during Phase 1.1 research
3. Reference the closest existing UI patterns identified by research agents (e.g., "delegation-acceptance-modal.tsx is the template for accept/decline flows")
4. Include brand-critical constraints if `USER_BRAND_CRITICAL=true` (security-sensitive surfaces need explicit callouts)

**After the agent completes**, reference the wireframe paths in the brainstorm document's Key Decisions table (add a "Visual design" row) and in the spec's Functional Requirements (link each FR to its wireframe). Commit wireframes alongside other brainstorm artifacts in Phase 3.6 step 6.

**Phase 3.55b — Wireframe review pause.** The ux-design-lead agent ends Step 3 by running `xdg-open <screenshots-directory>` so the wireframes are already open on screen when control returns here. But a Task subagent cannot collect operator input (`2026-05-12-task-subagent-prompt-text-only.md`), so the actual review pause must live in this orchestrator, immediately after the agent returns. This is the Phase N.5 mode-branch defense-in-depth gate (`2026-03-27-skill-defense-in-depth-gate-pattern.md`): always run, branch on mode.

- **Interactive arm** (operator present): `AskUserQuestion` — "Wireframes are open for review at `<screenshots-dir>` (the design agent ran `xdg-open`). Approve and continue, or request changes?" Options: **Approve** → **record the approved design's aesthetic direction to the taste-profile** (the agent surface's write path — the `ux-design-lead` agent never writes taste itself; #5990/ADR-090): `bash plugins/soleur/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md <context> aesthetic-direction <approved-direction> "$(date -u +%F)"` where `<context>` is the design's surface (`landing-page|marketing-site|dashboard|app-ui|docs|email|component`) and `<approved-direction>` is the winning direction as a sanitized lowercase-hyphen token; then proceed to Phase 3.6. **Request changes** → collect a free-text note, re-invoke `ux-design-lead` (Agent tool) with `feedback: <note>` plus the existing `.pen` path, let it re-export + re-open the folder, then re-ask. **Loop until Approve** — the Approve branch is the only exit (no dead end).
- **Headless / pipeline arm** (`HEADLESS_MODE=true`, no TTY, `/soleur:one-shot`, `/soleur:go --headless` — the same predicate as Phase 0.4 at `:101`): **do NOT pause.** Echo `Phase 3.55b: pipeline mode — wireframes ready for async review at <dir>` to the operator terminal and continue. This honors `one-shot/SKILL.md:11` ("no per-phase approval gates") and the mid-pipeline-pause anti-pattern (`2026-05-12-mid-plan-pause-gates-and-operator-step-pushback.md`); pausing here would hang the autonomous run.

**Why:** wireframes are a visual artifact the operator must eyeball before the design propagates into the spec — code is regenerable, wireframes are not (`2026-03-29-ux-gate-commit-checkpoints.md`). The mode branch is load-bearing: the pause fires only in interactive sessions and is suppressed entirely in headless mode (the duplicated mode predicate is kept identical to brainstorm `:101` and plan step 4b on purpose — update all copies together).

**Pencil unavailable → auto-install, then hard-block (never skip).** If Pencil tools (`mcp__pencil__batch_design`) are not connected — including `HEADLESS_MODE=true`, which is NOT an exemption (headless `.pen` authoring works) — run the `pencil-setup --auto` flow (`bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/pencil-setup/scripts/check_deps.sh --auto`, which installs `@pencil.dev/cli` to `~/.local` via npm, no sudo/display; auth via `PENCIL_CLI_KEY` from Doppler `soleur/dev`), then re-check `mcp__pencil__*` and author the `.pen`. **Before declaring the hard-block, load the key into the environment and re-check** — `check_deps.sh` reports `auth failed` on an *unloaded* key even when the key exists in Doppler and the MCP adapter is already connected: `export PENCIL_CLI_KEY="$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)"` then re-run check_deps, AND confirm in-session tools via `claude mcp list | grep pencil` (a `✓ Connected` adapter authors `.pen` files regardless of the bare-CLI auth-check). A headless Desktop AppImage core-dump (`Trace/breakpoint trap`) is the expected fall-through to headless CLI, not a blocker. See `knowledge-base/project/learnings/2026-06-04-pencil-headless-key-from-doppler-before-hardblock.md`. **Hard-block only** if auth is genuinely unsatisfiable (no key in Doppler + no interactive login + no connected adapter) or Node < 22.9.0, with a single instruction:

```
Phase 3.55 hard-block: wireframes are mandatory for this UI feature and Pencil could not be
auto-installed. Provision PENCIL_CLI_KEY in Doppler soleur/dev (or `pencil login`), or install
Node ≥ 22.9.0, then re-run brainstorm. (No Markdown/ASCII fallback — headless .pen authoring is
the only supported path.)
```

Do NOT record a "skipped" outcome and proceed — the only terminal states are `.pen` committed or this hard-block.

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
2. **Refine design further** - Continue exploring
3. **Done for now** - Return later

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
Run `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/project/brainstorms/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "brainstorm: archive <topic>"`.

## Important Guidelines

- **Stay focused on WHAT, not HOW** - Implementation details belong in the plan
- **Ask one question at a time** - Don't overwhelm
- **Apply YAGNI** - Prefer simpler approaches
- **Keep outputs concise** - 200-300 words per section max

NEVER CODE! Just explore and document decisions.
