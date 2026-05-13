---
name: plan
description: "This skill should be used when transforming feature descriptions into well-structured project plans following conventions."
---

# Create a plan for a new feature or bug fix

## Introduction

**Note: The current year is 2026.** Use this when dating plans and searching for recent documentation.

Transform feature descriptions, bug reports, or improvement ideas into well-structured markdown files issues that follow project conventions and best practices. This command provides flexible detail levels to match your needs.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

Do not proceed until you have a clear feature description from the user.

### 0. Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: plan cannot run on main/master. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).

**Check for knowledge-base directory and load context:**

Check if `knowledge-base/` directory exists. If it does:

1. Run `git branch --show-current` to get the current branch name
2. If the branch starts with `feat-`, read `knowledge-base/project/specs/<branch-name>/spec.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during planning
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` - use principles to guide planning decisions. Skip if already loaded (e.g., from a preceding `/soleur:brainstorm`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/spec.md` if it exists - use as planning input
5. Announce: "Loaded constitution and spec for `feat-<name>`"

**If knowledge-base/ does NOT exist:**

- Continue with standard planning flow

### 0.5. Idea Refinement

**Check for brainstorm output first:**

Before asking questions, look for recent brainstorm documents in `knowledge-base/project/brainstorms/` that match this feature:

```bash
ls -la knowledge-base/project/brainstorms/*.md 2>/dev/null | head -10
```

**Relevance criteria:** A brainstorm is relevant if:

- The topic (from filename or YAML frontmatter) semantically matches the feature description
- Created within the last 14 days
- If multiple candidates match, use the most recent one

**If a relevant brainstorm exists:**

1. Read the brainstorm document
2. Announce: "Found brainstorm from [date]: [topic]. Using as context for planning."
3. Extract key decisions, chosen approach, and open questions
4. **Skip the idea refinement questions below** - the brainstorm already answered WHAT to build
5. Proceed to Phase 1 -- **all sub-phases still apply** (1, 1.5, 1.5b, 1.6). Having a brainstorm skips idea refinement only, not community discovery or research.

**If multiple brainstorms could match:**
Use **AskUserQuestion tool** to ask which brainstorm to use, or whether to proceed without one.

**If no brainstorm found (or not relevant), run idea refinement:**

Refine the idea through collaborative dialogue using the **AskUserQuestion tool**:

- Ask questions one at a time to understand the idea fully
- Prefer multiple choice questions when natural options exist
- Focus on understanding: purpose, constraints and success criteria
- **Directional ambiguity gate:** If the task involves merging, moving, or restructuring (A into B vs B into A), explicitly confirm the direction with the user before proceeding -- even in pipeline mode. Code evidence can be wrong (see learning: 2026-03-17-planning-direction-confirmation-required)
- Continue until the idea is clear OR user says "proceed"

**Gather signals for research decision.** During refinement, note:

- **User's familiarity**: Do they know the codebase patterns? Are they pointing to examples?
- **User's intent**: Speed vs thoroughness? Exploration vs execution?
- **Topic risk**: Security, payments, external APIs warrant more caution
- **Uncertainty level**: Is the approach clear or open-ended?

**Skip option:** If the feature description is already detailed, offer:
"Your description is clear. Should I proceed with research, or would you like to refine it further?"

## Main Tasks

### 1. Local Research (Always Runs - Parallel)

<thinking>
First, I need to understand the project's conventions, existing patterns, and any documented learnings. This is fast and local - it informs whether external research is needed.
</thinking>

Run these agents **in parallel** to gather local context:

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, CLAUDE.md guidance, technology familiarity, pattern consistency
- **Learnings:** documented solutions in `knowledge-base/project/learnings/` that might apply (gotchas, patterns, lessons learned)

These findings inform the next step.

### 1.4. Network-Outage Hypothesis Check (Conditional)

If the feature description matches any of the patterns `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive substring match on the feature description), read [plan-network-outage-checklist.md](./references/plan-network-outage-checklist.md) and require its output in the `## Hypotheses` section of the final plan.

Also fire this gate when the feature description names `terraform apply` (with or without `-target=`) against a resource whose definition contains `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block. The provisioner block makes SSH a hard apply-time dependency that the prose-only keyword scan won't detect. **Why:** #3061 — apply on `terraform_data.deploy_pipeline_fix` hit `ssh: handshake failed: connection reset by peer` despite zero SSH keywords in the plan, because the firewall allowlist had drifted out from under the operator's egress IP.

The checklist enforces an L3->L7 diagnostic order: firewall allow-list and DNS/routing MUST be verified before sshd/fail2ban/service-layer hypotheses. Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`, this is a hard rule -- plans that propose sshd or fail2ban fixes without first verifying firewall + egress IP are workflow violations.

When a trigger pattern matches, emit rule-application telemetry so the weekly aggregator records this gate fired (see AGENTS.md `hr-ssh-diagnosis-verify-firewall`):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-ssh-diagnosis-verify-firewall applied \
  "When a plan addresses an SSH/network-connectivity s"
```

This step is a single file read, not a subagent spawn. If the feature description does not match any trigger pattern, skip this step silently.

### 1.5. Community Discovery Check (Conditional)

**Read `plugins/soleur/skills/plan/references/plan-community-discovery.md` now** for the full community discovery procedure (stack detection, coverage gap check, agent-finder). Skip if no uncovered stacks detected.

### 1.5b. Functional Overlap Check

**Read `plugins/soleur/skills/plan/references/plan-functional-overlap.md` now** for the functional overlap check procedure (always runs, spawns functional-discovery agent).

### 1.6. Research Decision

Based on signals from Step 0 and findings from Step 1, decide on external research.

**High-risk topics → always research.** Security, payments, external APIs, data privacy. The cost of missing something is too high. This takes precedence over speed signals.

**Strong local context → skip external research.** Codebase has good patterns, CLAUDE.md has guidance, user knows what they want. External research adds little value.

**Uncertainty or unfamiliar territory → research.** User is exploring, codebase has no examples, new technology. External perspective is valuable.

**Announce the decision and proceed.** Brief explanation, then continue. User can redirect if needed.

Examples:

- "Your codebase has solid patterns for this. Proceeding without external research."
- "This involves payment processing, so I'll research current best practices first."

### 1.6b. External Research (Conditional)

**Only run if Step 1.6 indicates external research is valuable.**

Run these agents in parallel:

- Task best-practices-researcher(feature_description)
- Task framework-docs-researcher(feature_description)

### 1.7. Consolidate Research

After all research steps complete, consolidate findings:

- Document relevant file paths from repo research (e.g., `app/services/example_service.rb:42`)
- **Include relevant institutional learnings** from `knowledge-base/project/learnings/` (key insights, gotchas to avoid)
- Note external documentation URLs and best practices (if external research was done)
- List related issues or PRs discovered
- Capture CLAUDE.md conventions
- **Reconcile spec claims against codebase reality.** If the repo-research-analyst returned any "Gap callouts" or equivalent mismatches, the plan MUST include a "Research Reconciliation — Spec vs. Codebase" section (3-column table: spec claim / reality / plan response) placed between "Overview" and "Implementation Phases". This prevents the plan from inheriting spec fiction (e.g., claimed infrastructure that doesn't exist) as phase estimates. See `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`.

**Optional validation:** Briefly summarize findings and ask if anything looks off or missing before proceeding to planning.

### 1.7.5. Code-Review Overlap Check

After the plan draft has enumerated its `## Files to Edit` and `## Files to Create` sections (i.e., run this check AFTER Step 2 Issue Planning produces the file list, and BEFORE Step 4 Detail Level selection), verify whether any open code-review issues touch files the plan intends to modify. This prevents two failure modes:

- **Rework:** a pre-existing scope-out names a file the plan will rewrite — if unnoticed, the plan ships, then the scope-out surfaces and drives a second refactor PR that could have been folded in.
- **Double-counting:** the review phase files a new scope-out for a concern a still-open issue already tracks.

**Procedure:**

1. Read the plan's `## Files to Edit` and `## Files to Create` sections (the plan draft exists by this point). Extract every file path. If the plan is still being drafted and those sections are not yet written, defer this check until they exist rather than guessing from the feature description — guessing produces false negatives.

2. Query open code-review issues. **Use two-stage piping (`--json` then a standalone `jq --arg`), not single-stage `gh --jq` with `--arg`.** The `gh` CLI does NOT forward `--arg` to its embedded jq; a single-stage form produces `unknown arguments` at runtime. See learning `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

    ```bash
    gh issue list --label code-review --state open \
      --json number,title,body --limit 200 > /tmp/open-review-issues.json
    ```

3. For each planned file path, search the issue bodies using standalone `jq` with `--arg` (safe against regex metacharacters in paths):

    ```bash
    jq -r --arg path "<file-path>" '
      .[] | select(.body // "" | contains($path))
      | "#\(.number): \(.title)"
    ' /tmp/open-review-issues.json
    ```

4. If any matches are returned, write a `## Open Code-Review Overlap` section to the plan file with a one-line bullet per match and an explicit disposition for each:

    > X open scope-outs touch these files: #2466 (Range cache), #2483 (helper extraction). Fold in / acknowledge / defer: …

    For each match, the planner MUST explicitly choose one of:

    - **Fold in:** plan extends to close the scope-out in the same PR. Add the scope-out's file paths to `## Files to edit` and note `Closes #<N>` in the PR-body reminder.
    - **Acknowledge:** plan deliberately does NOT fix the scope-out (e.g., different concern, needs its own cycle). Record a 1-sentence rationale. The scope-out remains open.
    - **Defer:** plan is not the right place; update the scope-out issue with a re-evaluation note (e.g., "revisit after feat-X lands"). Do NOT silently leave the overlap unaddressed — the reviewer will re-surface it.

5. If no matches, still record `## Open Code-Review Overlap` with `None` so the next planner can see the check ran.

**Why this matters:** In the 2026-04-17 window, PR #2486 closed three scope-outs (#2467 + #2468 + #2469) because the planner noticed the overlap. PRs #2463 and #2477 grew the backlog instead because no overlap check ran. This phase makes the #2486 pattern the default, not the exception. See `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md`.

### 2. Issue Planning & Structure

<thinking>
Think like a product manager - what would make this issue clear and actionable? Consider multiple perspectives
</thinking>

**Title & Categorization:**

- [ ] Draft clear, searchable issue title using conventional format (e.g., `feat: Add user authentication`, `fix: Cart total calculation`)
- [ ] Determine issue type: enhancement, bug, refactor
- [ ] Convert title to filename: add today's date prefix, strip prefix colon, kebab-case, add `-plan` suffix
  - Example: `feat: Add User Authentication` → `2026-01-21-feat-add-user-authentication-plan.md`
  - Keep it descriptive (3-5 words after prefix) so plans are findable by context

**Stakeholder Analysis:**

- [ ] Identify who will be affected by this issue (end users, developers, operations)
- [ ] Consider implementation complexity and required expertise

**Content Planning:**

- [ ] Choose appropriate detail level based on issue complexity and audience
- [ ] List all necessary sections for the chosen template
- [ ] Gather supporting materials (error logs, screenshots, design mockups)
- [ ] Prepare code examples or reproduction steps if applicable, name the mock filenames in the lists
- [ ] When planning a directory rename, enumerate ALL files in the target directory as potential self-reference holders -- directory trees and conceptual prose derived from the directory name don't match path-pattern greps
- [ ] When the plan prescribes scoping a helper function by a new column/predicate, `rg` the codebase for every other inline query on the same table that BYPASSES the helper (id-based lookups, pre-helper historical queries, WS-handler inline SELECTs) and list each as a `Files to Edit` entry -- sibling queries are the most common silent backdoor after a tenant-scope change. See learning `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md`.
- [ ] When the plan prescribes any path glob (e.g., `apps/foo/**`, `**/doppler*.{yml,yaml,sh}`, `.github/workflows/*foo*.yml`), verify each glob matches ≥1 real file via `git ls-files | grep -E '<translated-glob>'` AND for negative-coverage gates (security gates, denylist filters, sensitive-path detectors) enumerate sibling files at the same architectural depth — globs constructed from a plan miss files the plan never inventoried. See AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g` and learning `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md`.
- [ ] **Wrapper-vs-curl check before adopting a workflow wrapper.** Before prescribing `claude-code-action`, `peter-evans/create-pull-request`, or any wrapper that constrains workflow architecture (token-revoking post-steps, hardcoded auto-merge, mandated job ordering), ask: "what does this look like as 5 lines of `curl` + `jq`?" If the answer is "fine," skip the wrapper. The wrapper's value is in agent tool-use loops or PR-creation generality; a single-shot LLM call or single-PR workflow doesn't need it. **Why:** 2026-05-11 #2720 v1 plan adopted `claude-code-action` and contorted into a two-job split + matrix to dodge its post-step token revocation; v2 dropped the wrapper and 4 P0 issues dissolved. See `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.
- [ ] **Paper-resolution lint.** Every FR/AC added to fold a review finding MUST cite the implementation location — e.g., `<script-file>:<line>`, `<workflow-file>:<section>`, or `prompt:step-N`. Without the pointer, the FR is paper — the planner could not encode the fix in code, only in prose, and the implementer will discover the gap at /work time. **Why:** 2026-05-11 #2720 v1 plan folded 6 spec-flow P0s as FRs/ACs; spec-flow re-validation against the plan caught 4 as "RESOLVED in spec, NOT IMPLEMENTED in code." Same learning file.

### 2.5. Domain Review Gate

After generating the plan structure, assess which business domains this plan has implications for. This gate enforces constitution line 122: plans must receive cross-domain review before implementation.

**Step 1 — Domain Sweep:**

1. **Brainstorm carry-forward check:** If the brainstorm document (loaded in Phase 0.5) contains a `## Domain Assessments` section, carry forward the findings. Extract relevant domains and their summaries. Skip fresh assessment.

2. **Fresh assessment (if no brainstorm or no `## Domain Assessments` section):** Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Assess all 8 domains against the plan content in a single LLM pass using each domain's Assessment Question. Use semantic assessment — not keyword matching.

3. **Spawn domain leaders:** For each domain assessed as relevant **except Product** (handled in Step 2), spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md, substituting `{desc}` with the plan summary. Spawn in parallel if multiple are relevant.

4. **Collect findings:** Wait for all domain leader Tasks to complete. Each returns a brief structured assessment. If a domain leader Task fails (timeout, error), write partial findings for that domain with `Status: error` and continue with remaining domains.

**Step 1.5 — Brainstorm Specialist Carry-Forward Gate:**

After domain sweep, scan the brainstorm document's `## Domain Assessments` section (and any `## Capability Gaps` section) for domain leaders that recommended specific specialists by name (e.g., "delegates to conversion-optimizer", "recommends copywriter for cancellation copy", "invoke ux-design-lead for wireframes"). Build a `REQUIRED_SPECIALISTS` list from these recommendations.

For each specialist in `REQUIRED_SPECIALISTS`:

1. If the specialist will be invoked by the Product/UX Gate pipeline below (ux-design-lead, copywriter, spec-flow-analyzer), mark it as "covered by UX Gate" — it will run in Step 2.
2. If the specialist is NOT covered by the UX Gate pipeline (e.g., conversion-optimizer, retention-strategist, pricing-strategist), invoke it as a Task now with a scoped prompt derived from the recommendation context. Spawn in parallel if multiple.
3. Record all brainstorm-recommended specialists in the Domain Review section under `**Brainstorm-recommended specialists:**`.

**Enforcement:** Specialists recommended by name in brainstorm domain assessments MUST be either invoked or explicitly declined by the user via AskUserQuestion ("Domain leader recommended [specialist] for [reason]. Run now / Skip with acknowledgment"). Silent skipping is a workflow violation. **Why:** In #1078, the CMO recommended conversion-optimizer and copywriter for the cancellation flow, but the plan skill silently wrote them into `Skipped specialists:` without asking, producing UX artifacts that lacked brand review.

**Step 2 — Product/UX Gate:**

After Steps 1 and 1.5 complete, if Product domain was flagged as relevant, run the existing three-tier classification:

- **BLOCKING**: Creates new user-facing pages, multi-step user flows, or significant new UI components — including modals, dialogs, confirmation flows, and interstitials with emotional or persuasive copy (e.g., signup flows, dashboards, onboarding wizards, chat interfaces, retention modals, cancel confirmation screens, prompts, banners)
- **ADVISORY**: Modifies existing user-facing pages or components without adding new interactive surfaces (e.g., layout changes, form updates, adding fields to existing screens)
- **NONE**: No user-facing impact

A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE.

**Mechanical escalation (overrides subjective assessment):** Scan the plan's "Files to create" list. If any new file path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, the tier is **BLOCKING** regardless of subjective assessment. Creating a new component file = new user-facing surface = UX review required. **Why:** In #1049, a notification prompt component was classified as ADVISORY because the agent judged it "not significant enough." The user had to manually trigger the UX gate post-plan.

**On BLOCKING:**

1. Run spec-flow-analyzer via Task with UI-flow-aware prompt: "Analyze the user flows in this plan. Map each screen, identify entry/exit points, dead ends, missing error states, and flows that drop the user. Focus on user journey completeness, not technical implementation."
2. Run CPO via Task with scoped prompt: "Assess the product implications of this plan: {plan summary}. Cross-reference against brand-guide.md and constitution.md. Identify product strategy concerns, flow gaps, and positioning issues. Output a structured advisory — do not use AskUserQuestion."
3. **Brainstorm carry-forward check.** Before invoking ux-design-lead, check the UX signal source. If the only UX validation is brainstorm carry-forward (brainstorm assessed the *idea*, not the *page design*), reject it: "Brainstorm validated the idea, not the page design. Proceeding to wireframes." Then continue to step 4. This check applies to BLOCKING tier only — ADVISORY and NONE tiers may still carry forward brainstorm UX findings.
4. Invoke ux-design-lead via Task with scoped prompt: "Create wireframes for these user flows: {flow list}. Platform: desktop. Fidelity: wireframe." The agent has its own Pencil MCP prerequisite check — if Pencil is unavailable, the agent will stop with an installation message. If the Task returns without wireframes (agent self-stopped), write `Pencil available: no` in the Domain Review section, add `ux-design-lead` to `**Skipped specialists:**` with the user's justification, and display: "ux-design-lead skipped (Pencil MCP not available). Consider running wireframes manually before implementation."
5. **Content Review Gate.** Check if any domain leader (CMO, CRO, CPO, or other) recommended a copywriter or content specialist in their Step 1 assessment. If yes: invoke copywriter agent via Task with prompt: "Review the planned page content for brand voice compliance, value proposition clarity, and messaging effectiveness. Reference brand-guide.md." If copywriter ran successfully, add `copywriter` to `**Agents invoked:**`. If user declines, add `copywriter` to `**Skipped specialists:**` with the user's reason. If copywriter agent fails (timeout, error), add `copywriter` to `**Skipped specialists:**` with note `(agent error — review manually)` and set `**Decision:** reviewed (partial)`. If no domain leader recommended a copywriter, skip this step silently. This gate also fires on ADVISORY tier when a domain leader recommended a copywriter — the recommendation is the signal, not the tier.
6. Phase 3 SpecFlow is skipped (spec-flow-analyzer already ran in step 1 with UI-aware prompt — avoids duplicate invocation).
7. If any agent in the pipeline fails (timeout, error), write partial findings with `Decision: reviewed (partial)`. **BLOCKING gate enforcement:** If the tier is BLOCKING and any required specialist (ux-design-lead, copywriter, spec-flow-analyzer) failed, do NOT silently proceed. Instead, use AskUserQuestion to present: "BLOCKING Product/UX Gate: [specialist] failed ([reason]). UX artifacts are required before implementation (AGENTS.md). How to proceed?" Options: (a) **Retry now** — re-invoke the failed agents, (b) **Skip with acknowledgment** — proceed without UX artifacts (user accepts the risk), (c) **Defer to next session** — save partial plan, run UX gate when agents are available. Record the user's choice in the Domain Review section. For ADVISORY tier or non-specialist agents, proceed silently with partial findings as before.

**On ADVISORY:**

1. If in pipeline/subagent context (plan file path was provided as argument, not interactive): auto-accept, write Product/UX Gate subsection with `Tier: advisory, Decision: auto-accepted (pipeline)`, proceed silently.
2. If interactive: display notice via AskUserQuestion: "This plan modifies existing UI. Run UX review?" Options: "Yes, run full review" / "Skip — I'll handle UX manually". Record choice.
3. If user chooses full review, run the BLOCKING pipeline above.
4. **Content Review Gate (ADVISORY).** Regardless of the UX review choice, if any domain leader recommended a copywriter or content specialist, run step 5 from the BLOCKING pipeline (Content Review Gate). The recommendation is the signal, not the tier — modifying existing copy still benefits from content review.

**On NONE:** Skip — no Product/UX Gate subsection needed beyond the domain sweep finding.

If Product domain was NOT flagged as relevant in the sweep, skip Step 2 entirely.

**Writing the `## Domain Review` section:**

After both steps complete, write the `## Domain Review` section to the plan file using the heading contract below.

**`## Domain Review` Heading Contract:**

```markdown
## Domain Review

**Domains relevant:** [comma-separated list] | none

### [Domain Name] (one subsection per relevant non-Product domain)

**Status:** reviewed | error
**Assessment:** [leader's structured assessment summary]

### Product/UX Gate (only if Product domain relevant and tier is BLOCKING or ADVISORY)

**Tier:** blocking | advisory
**Decision:** reviewed | reviewed (partial) | skipped | auto-accepted (pipeline)
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter | [subset] | none
**Skipped specialists:** ux-design-lead (<reason>), copywriter (<reason>) | none
**Pencil available:** yes | no | N/A

#### Findings

[Agent findings summary]
```

When NO domains are relevant:

```markdown
## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
```

Place after Acceptance Criteria, before Test Scenarios (or before the last major section). If the plan lacks an Acceptance Criteria heading, place before the last major section or at the end of the plan.

### 2.6. User-Brand Impact Section (Always)

Every plan MUST include a `## User-Brand Impact` section. This is the framing-time enforcement of AGENTS.md `hr-weigh-every-decision-against-target-user-impact` and the gate that catches the #2887-class blind spot — decisions weighed on technical and convenience axes only, with no question asked about what one user's breach would cost the brand.

**Step 1 — Insert the section.** If the plan draft does not yet contain a `## User-Brand Impact` heading, insert one using the template from `plugins/soleur/skills/plan/references/plan-issue-templates.md`. The section MUST appear between the description and the Acceptance Criteria. The three required lines:

- `**If this lands broken, the user experiences:**` — name a concrete, user-facing artifact.
- `**If this leaks, the user's [data / workflow / money] is exposed via:**` — name a concrete exposure vector.
- `**Brand-survival threshold:** none | single-user incident | aggregate pattern` — choose one.

**Step 2 — Brainstorm carry-forward.** If the brainstorm document loaded in Phase 0.5 contains a `## User-Brand Impact` framing (which it should when brainstorm Phase 0.1 set `USER_BRAND_CRITICAL=true`), import the threshold and the artifact/vector declarations directly rather than re-authoring. Carry-forward is preferred — re-authoring at plan time risks drift from the brainstormed framing.

**Step 3 — Threshold-driven sign-off requirement.** If the threshold resolves to `single-user incident`:

1. Add `requires_cpo_signoff: true` to the plan's YAML frontmatter.
2. Display: "CPO sign-off required at plan time before `/work` begins. Invoke CPO domain leader if not already covered by Phase 2.5 carry-forward, or confirm CPO has reviewed the brainstorm."
3. Note in the plan that `user-impact-reviewer` will be invoked at review-time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

**Sign-off lifecycle staging — who participates at which phase:**

The set of mandatory leaders changes by lifecycle phase, and that is by design — different leaders weigh in at different decision points:

- **Brainstorm phase (framing time):** CPO + CLO + CTO are spawned in parallel when `USER_BRAND_CRITICAL=true`. Rationale: the approach has not been chosen yet, so all three lenses (product blast-radius framing, legal/compliance, architectural blast-radius) need to land before the plan exists. See `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## User-Brand-Critical Tag Processing`.
- **Plan phase (this gate):** CPO sign-off only. Rationale: the plan implements the approach already framed by all three brainstorm leaders; the plan-time sign-off is the single product-owner ack on the technical approach. CLO and CTO concerns from brainstorm should be reflected in the plan body (Risks section, Sharp Edges, Domain Review carry-forward) — they do not re-sign here.
- **Review phase (PR time):** CPO is not re-invoked; instead the `user-impact-reviewer` agent enumerates failure modes against the diff. Rationale: review-time concerns are diff-shaped, not approach-shaped.
- **Ship phase (preflight Check 6):** No human sign-off; mechanical gate that the section exists and the threshold is valid.

This tiered model is intentional — re-asking CPO/CLO/CTO at every phase would dilute the framing into ceremony. The framing question is asked once (brainstorm), the answer is locked in (plan), the diff is checked against the answer (review), the gate verifies the answer was given (ship).

If the threshold resolves to `aggregate pattern`, no per-PR sign-off is added but the section must still be present.

If the threshold resolves to `none` AND the diff touches a sensitive path (canonical regex defined in `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1), the section MUST contain a `threshold: none, reason: <one-sentence non-empty reason>` scope-out bullet. Without it, preflight will FAIL at ship time.

**Step 4 — Sharp-edge note.** When emitting the final plan output, add a Sharp Edges entry:

> A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

**Why:** Triggered by #2887 — the dev/prd Doppler-config collapse shipped for months because every existing gate weighed the decision on technical and convenience axes only. The framing-time enforcement here, combined with deepen-plan Phase 4.6 (halt on missing section), preflight Check 6 (ship-time gate), and the `user-impact-reviewer` conditional agent, closes the workflow-level loop.

### 2.7. GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

If the plan touches regulated-data surfaces (per the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex — schemas, migrations, auth flows, API routes, `.sql` files), invoke `/soleur:gdpr-gate` against the plan doc + the FR/TR sections being authored. Output is advisory-only with mandatory disclaimer; Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 trigger) prompt operator-acknowledged write to `compliance-posture.md` Active Items + GitHub issue with label `compliance/critical`.

**Also invoke when canonical regex misses but ANY of these hold:** (a) new processing activity using LLM/external API on operator-session-derived data, (b) brand-survival threshold `single-user incident` declared in the plan, (c) new cron/workflow that READS from `knowledge-base/project/learnings/` or `knowledge-base/project/specs/`, (d) new artifact distribution surface (plugin update, public PR body, package release). The canonical regex covers schema/auth/API code surfaces; these four expand coverage to cross-controller data-movement surfaces. **Why:** 2026-05-11 #2720 — plan touched none of the regex surfaces but added Anthropic-bound LLM-summarization of operator-session learnings + draft PRs to public repo; gate-time invocation surfaced a pre-existing Anthropic-DPA gap that no other gate caught. See `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.

Skip silently if no regulated-data surface is touched AND none of the (a)-(d) triggers fire.

### 3. SpecFlow Analysis

**If spec-flow-analyzer was already invoked in Phase 2.5, skip this phase and proceed to Phase 4.**

After planning the issue structure, run SpecFlow Analyzer to validate and refine the feature specification. SpecFlow is especially valuable for CI/workflow and infrastructure changes where bash conditional logic can silently drop edge cases that human review misses.

- Task spec-flow-analyzer(feature_description, research_findings)

**SpecFlow Analyzer Output:**

- [ ] Review SpecFlow analysis results
- [ ] Incorporate any identified gaps or edge cases into the issue
- [ ] Update acceptance criteria based on SpecFlow findings

### 4. Choose Implementation Detail Level

**Read `plugins/soleur/skills/plan/references/plan-issue-templates.md` now** to load the three issue templates (MINIMAL, MORE, A LOT). Select the appropriate detail level based on complexity -- simpler is mostly better. Use the template structure from the reference file for the chosen level.

### 5. Issue Creation & Formatting

<thinking>
Apply best practices for clarity and actionability, making the issue easy to scan and understand
</thinking>

**Content Formatting:**

- [ ] Use clear, descriptive headings with proper hierarchy (##, ###)
- [ ] Include code examples in triple backticks with language syntax highlighting
- [ ] Add screenshots/mockups if UI-related (drag & drop or use image hosting)
- [ ] Use task lists (- [ ]) for trackable items that can be checked off
- [ ] Add collapsible sections for lengthy logs or optional details using `<details>` tags
- [ ] Apply appropriate emoji for visual scanning (🐛 bug, ✨ feature, 📚 docs, ♻️ refactor)

**Cross-Referencing:**

- [ ] Link to related issues/PRs using #number format
- [ ] Reference specific commits with SHA hashes when relevant
- [ ] Link to code using GitHub's permalink feature (press 'y' for permanent link)
- [ ] Mention relevant team members with @username if needed
- [ ] Add links to external resources with descriptive text

**Code & Examples:**

````markdown
# Good example with syntax highlighting and line references


```ruby
# app/services/user_service.rb:42
def process_user(user)

# Implementation here

end
```

# Collapsible error logs

<details>
<summary>Full error stacktrace</summary>

`Error details here...`

</details>
````

**AI-Era Considerations:**

- [ ] Account for accelerated development with AI pair programming
- [ ] Include prompts or instructions that worked well during research
- [ ] Note which AI tools were used for initial exploration (Claude, Copilot, etc.)
- [ ] Emphasize comprehensive testing given rapid implementation
- [ ] Document any AI-generated code that needs human review

### 6. Final Review & Submission

**Pre-submission Checklist:**

- [ ] Title is searchable and descriptive
- [ ] Labels accurately categorize the issue
- [ ] All template sections are complete
- [ ] Links and references are working
- [ ] Acceptance criteria are measurable
- [ ] Add names of files in pseudo code examples and todo lists
- [ ] Add an ERD mermaid diagram if applicable for new model changes
- [ ] **Browser task automation check:** Scan all tasks for steps labeled "manual", "browser", or "user must". If any task involves browser interaction (account creation, form submission, settings configuration, credential generation), rewrite it as a Playwright MCP automation step. The only genuinely manual browser steps are CAPTCHA solving and interactive OAuth consent -- and even those should be automated up to the CAPTCHA/consent gate, then handed to the user for that single interaction.
- [ ] **Deferral tracking check:** Scan the plan's "Alternative Approaches Considered" table and any "Non-Goals" or "Out of Scope" sections for items explicitly deferred to a later phase. For each deferred item, create a GitHub issue with: what was deferred, why, re-evaluation criteria, and milestone from `knowledge-base/product/roadmap.md`. A deferral without a tracking issue is invisible.
- [ ] **CLI-verification gate (#2566):** For every CLI invocation the plan prescribes to land in user-facing docs (`*.njk`, `*.md`, README, `apps/**`), verify the tokens exist. One of: (a) run `<tool> --help` or `<tool> <subcommand> --help` locally and paste the relevant line into Research Insights; (b) cite the tool's official command reference URL; (c) annotate the plan snippet with `<!-- verified: YYYY-MM-DD source: <url> -->`. A plan that embeds a CLI invocation without ONE of the three MUST NOT ship -- silence (omit the snippet) beats fabrication. `tsc` and Eleventy build do NOT catch fabricated tokens. **Why:** #1810/#2550 shipped `ollama launch claude --model gemma4:31b-cloud` -- every token fabricated, caught 8 days later.

## Output Format

**Filename:** Use the date and kebab-case filename from Step 2 Title & Categorization.

```text
knowledge-base/project/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md
```

Examples:

- ✅ `knowledge-base/project/plans/2026-01-15-feat-user-authentication-flow-plan.md`
- ✅ `knowledge-base/project/plans/2026-02-03-fix-checkout-race-condition-plan.md`
- ✅ `knowledge-base/project/plans/2026-03-10-refactor-api-client-extraction-plan.md`
- ❌ `knowledge-base/project/plans/2026-01-15-feat-thing-plan.md` (not descriptive - what "thing"?)
- ❌ `knowledge-base/project/plans/2026-01-15-feat-new-feature-plan.md` (too vague - what feature?)
- ❌ `knowledge-base/project/plans/2026-01-15-feat: user auth-plan.md` (invalid characters - colon and space)
- ❌ `knowledge-base/project/plans/feat-user-auth-plan.md` (missing date prefix)

## Plan Review (Always Runs)

After writing the plan file, automatically run `/plan_review <plan_file_path>` to get feedback from three specialized reviewers in parallel:

- **DHH Rails Reviewer** - Challenges overengineering, enforces simplicity
- **Kieran Rails Reviewer** - Checks correctness, completeness, convention adherence
- **Code Simplicity Reviewer** - Ensures YAGNI, flags unnecessary complexity

**After review completes:**

1. Present consolidated feedback (agreements first, then disagreements)
2. Ask: "Apply these changes?" (Yes / Partially / Skip)
3. If Yes: apply all changes to the plan file
4. If Partially: ask which changes to apply, then apply selected changes
5. If Skip: continue unchanged

**Why Plan Review runs BEFORE Save Tasks:** `tasks.md` is a derivative breakdown of the plan's phases. If review prompts material changes (phase cuts, deliverable rewrites), generating `tasks.md` beforehand would immediately go stale and require regeneration. Running review first → applying changes → then deriving tasks ensures `tasks.md` reflects the final plan as a single source of truth, and the commit below covers both files in one atomic history entry.

## Save Tasks to Knowledge Base (if exists)

**After Plan Review has applied any requested changes**, generate `tasks.md` from the finalized plan and commit all artifacts together:

Check if `knowledge-base/` exists. If so, run `git branch --show-current` to get the current branch. If on a `feat-*` branch, create the spec directory with `mkdir -p knowledge-base/project/specs/<branch-name>`.

**If knowledge-base/ exists and on a feature branch:**

**Carry forward `lane:` from spec.md.** Extract using the canonical gsub awk pattern (matches `skill-security-scan/scripts/run-scan.sh:34`):

```bash
LANE=$(awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?|"?$/, ""); print; exit }' "knowledge-base/project/specs/feat-${branch_name}/spec.md")
```

Validate `LANE` against the 3-value enum (`single-domain`, `cross-domain`, `procedural`). If empty (legacy spec lacks `lane:`) or invalid (any other value), set `LANE=cross-domain` and echo to the operator terminal: `plan: spec lacks valid lane: — defaulted to cross-domain (fail-closed).` Add a one-line note to the plan body: `Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).` The plan file's YAML frontmatter MUST include `lane: <value>`.

1. **Generate tasks.md** using `spec-templates` skill template, derived from the finalized (post-review) plan:
   - Extract actionable tasks from the plan
   - Organize into phases (Setup, Core Implementation, Testing)
   - Use hierarchical numbering (1.1, 2.1, 2.1.1, etc.)

2. **Save tasks.md** to `knowledge-base/project/specs/feat-<name>/tasks.md`

3. **Announce:** "Tasks saved to `knowledge-base/project/specs/feat-<name>/tasks.md`. Use `skill: soleur:work` to implement."

4. **Commit and push plan artifacts:**

   Both the plan file and tasks.md are committed together so the final plan and its task breakdown land in the same history entry:

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/tasks.md
   git commit -m "docs: create plan and tasks for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue.

**If knowledge-base/ does NOT exist or not on feature branch:**

- Plan saved to `knowledge-base/project/plans/` only (current behavior)

## Exit Gate (direct invocation only)

**Pipeline detection:** If this skill is running inside a Task subagent (the conversation
contains a `RETURN CONTRACT` section from a Task delegation), skip the exit gate entirely.
Return the plan file path per the return contract. The calling pipeline handles compound
and lifecycle progression.

**If invoked directly by the user:**

1. Run `skill: soleur:compound` to capture learnings from the planning session.
   If compound finds nothing to capture, it will skip gracefully — do not block on this.
2. Verify all plan artifacts are committed and pushed. The Save Tasks section already
   committed the plan file and tasks.md. Run `git status --short` to check for any
   remaining uncommitted changes. If found:

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/
   git commit -m "docs: plan artifacts for feat-<name>"
   git push
   ```

   If there are no uncommitted changes, skip the commit. If push fails (no network),
   warn and continue.
3. Display the resume prompt (per AGENTS.md Communication rule). Format:

   ```text
   All artifacts are on disk. Run `/clear` then paste this to resume:

   /soleur:work <plan-file-path>

   Context: branch <branch>, worktree <worktree-path>, PR #<N>, issue #<N>.
   <one-line summary of what was already done>
   ```

   Replace placeholders with actual values from the session. The user must be
   able to paste the command and go without re-explaining context.

**Resume prompt (MANDATORY):** After the display message above, always output a copy-pasteable resume prompt block. This is required by AGENTS.md whenever `/clear` is mentioned. Format:

```text
Resume prompt (copy-paste after /clear):
/soleur:work <plan-path>. Branch: feat-<name>. Worktree: .worktrees/feat-<name>/. Issue: #<number>. PR: #<pr-number>. Plan reviewed, implementation next.
```

## Post-Generation Options

After plan review, use the **AskUserQuestion tool** to present these options:

**Resume prompt (MANDATORY — AGENTS.md Communication):** Before presenting the question, generate a copy-pasteable resume prompt containing: skill to run (`/soleur:work`), plan file path, branch name, worktree path, PR number, issue number, and a one-line summary of what was already done. Display it in a fenced code block so the user can paste it into a fresh session after `/clear`. This is the single most important output of the post-generation phase — without it, the user cannot resume in a new session without re-explaining context.

**Question:** "Plan reviewed and ready at `knowledge-base/project/plans/YYYY-MM-DD-<type>-<name>-plan.md`. Context is saved to disk — run `/clear` before `/soleur:work` for maximum headroom. What would you like to do next?"

**Options:**

1. **Open plan in editor** - Open the plan file for review
2. **Run `/deepen-plan`** - Enhance each section with parallel research agents (best practices, performance, UI)
3. **Start `soleur:work`** - Begin implementing this plan locally
4. **Start `soleur:work` on remote** - Begin implementing in Claude Code on the web (use `&` to run in background)
5. **Create Issue** - Create issue in project tracker (GitHub/Linear)
6. **Simplify** - Reduce detail level

Based on selection:

- **Open plan in editor** → Run `open knowledge-base/project/plans/<plan_filename>.md` to open the file in the user's default editor
- **`/deepen-plan`** → Call the /deepen-plan command with the plan file path to enhance with research
- **`soleur:work`** → Use `skill: soleur:work` with the plan file path
- **`soleur:work` on remote** → Use `skill: soleur:work` with `knowledge-base/project/plans/<plan_filename>.md` to start work in background for Claude Code web
- **Create Issue** → See "Issue Creation" section below
- **Simplify** → Ask "What should I simplify?" then regenerate simpler version
- **Other** (automatically provided) → Accept free text for rework or specific changes

**Note:** If running `soleur:plan` with ultrathink enabled, automatically use `skill: soleur:deepen-plan` after plan creation for maximum depth and grounding.

Loop back to options after Simplify or Other changes until user selects `soleur:work`.

## Issue Creation

When user selects "Create Issue", detect their project tracker from CLAUDE.md:

1. **Check for tracker preference** in user's CLAUDE.md (global or project):
   - Look for `project_tracker: github` or `project_tracker: linear`
   - Or look for mentions of "GitHub Issues" or "Linear" in their workflow section

2. **If GitHub:**

   Use the title and type from Step 2 (already in context - no need to re-read the file):

   ```bash
   gh issue create --title "<type>: <title>" --body-file <plan_path> --milestone "Post-MVP / Later"
   ```

   After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies: `gh issue edit <number> --milestone '<phase>'`.

3. **If Linear:**

   Read the plan file content, then run `linear issue create --title "<title>" --description "<plan content>"`.

4. **If no tracker configured:**
   Ask user: "Which project tracker do you use? (GitHub/Linear/Other)"
   - Suggest adding `project_tracker: github` or `project_tracker: linear` to their CLAUDE.md

5. **After creation:**
   - Display the issue URL
   - Ask if they want to proceed to `skill: soleur:work` or `skill: soleur:plan-review`

## Managing Plan Documents

**Update an existing plan:**
If re-running `soleur:plan` for the same feature, read the existing plan first. Update in place rather than creating a duplicate. Preserve prior content and mark changes with `[Updated YYYY-MM-DD]`.

**Archive completed plans:**
Run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/project/plans/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "plan: archive <topic>"`.

## Sharp Edges

- When a plan corrects a factual claim (e.g., updates a version range from X to Y), grep the plan output for the old incorrect value before finalizing. Subagents can echo stale data from their initial context even when their analysis concludes otherwise.
- When a plan adds `cloudflare_record` resources with `name = "@"`, flag it during plan review — the Cloudflare API normalizes `@` to the FQDN on storage, causing perpetual Terraform drift. Use the FQDN (e.g., `"soleur.ai"`) instead.
- When a plan prescribes a fix based on exit code semantics of shell commands, include a verification step: "Test each command's actual exit code in the target environment before implementing." Plans that assume exit codes without verification (e.g., assuming `git diff --cached --quiet` returns 128 in bare repos when it actually returns 1) lead to implementation pivots during GREEN phase.
- When a plan prescribes dependency upgrades within a major version range, specify the npm version tag explicitly (e.g., `npm install next@15`, not `npm install next@latest`). The `@latest` tag resolves globally and may cross major version boundaries.
- When a plan references specific dependency version ranges or peer constraints, verify them via `npm view <pkg> peerDependencies` before prescribing a fix approach. Plans have prescribed wrong version ranges that were only caught during implementation.
- When a plan adds a new required check to CI/branch protection rulesets, the plan MUST include an audit step that greps for ALL workflows creating PRs via `GITHUB_TOKEN` or `create-pull-request` action and lists each one requiring synthetic check updates. Plans that claim "only N workflows need updating" without showing the grep output are incomplete.
- When a plan prescribes Supabase/PostgREST query syntax (embedded resources, lateral joins, `.select()` with modifiers), include a verification note: "Confirm syntax against Supabase JS client docs before implementing." PostgREST embedded resource syntax is more limited than expected — chained `.limit().order().eq()` inside `select()` does not work.
- When prescribing `gh api` commands with array parameters, always use `--input -` with a heredoc JSON body instead of `--field`. The `--field` flag wraps values in quotes, turning JSON arrays into strings (HTTP 422). After any GitHub settings PATCH, immediately re-read settings to verify the change was applied — the repo API silently ignores some org-level features (returns 200 OK without state change).
- When generating test commands, always reference `package.json scripts.test` rather than assuming a runner (bun test, vitest, jest). Plans that hardcode a specific test runner can fail silently when the project uses a different framework.
- Before a plan's Test Strategy names a specific framework (bats, pytest, rspec, vitest, etc.), verify the framework is actually installed: `command -v <tool>` AND grep existing test files for the pattern (`ls plugins/*/test/`, `find . -name '*.bats' -o -name '*_test.*'`). If absent, default to the existing convention. Never prescribe a new test framework without an explicit "Add <framework> dependency" task AND reconciling with any "no new dependencies" claim in the plan Overview. **Why:** In #2212, the plan prescribed `bats` while also saying "no new dependencies" — bats was not installed; the implementer adapted to `.test.sh` convention at work-skill time, paying attention cost that a 2-line check in the plan would have avoided.
- When a plan prescribes a specific CLI invocation form (stdin/stdout pipes via `-`, particular long options, flag combinations that vary by tool version), the preflight task MUST exercise the exact form with realistic input — not just `--version` or `--help`. Installability ≠ usability: `--version` proves the tool exists; it proves nothing about whether the flags your helper depends on are recognized by the installed version. **Why:** In the #2456 PDF linearization plan, the initial preflight only ran `qpdf --version`. A reviewer challenged whether `qpdf --linearize - -` actually supports stdin/stdout pipes. Expanding preflight to pipe a real fixture PDF through the exact form (and `qpdf --check` the output) caught the ambiguity before implementation — a failure would have collapsed the helper design mid-build. See `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`.
- When a plan addresses alignment of a toggleable UI control (collapse/expand, accordion, drawer, tab visibility), verify alignment in **both toggle states** before writing the plan — not just the state named in the bug report. The two states often render different DOM subtrees with different parent geometry; a fix for one state can leave the other misaligned. Fold both states into the same PR, or document why only one state needs the fix. **Why:** PR #2494 fixed the collapsed-state settings-nav chevron but left the expanded-state chevron misaligned, requiring a follow-up PR #2504. The gap existed because the bug report mentioned only one state. See `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`.
- When a plan's Non-Goals or Risks section makes a claim about third-party vendor default behavior (Cloudflare cache eligibility, Supabase connection limits, Next.js body-size defaults, Stripe webhook retry semantics, AWS S3 consistency model), the claim MUST cite the specific doc URL and include a verification step — or drop the claim entirely. Asserting "the default handles this" without a citation is a plan-quality failure that downstream review agents have to catch. **Why:** In PR #2532, the plan asserted Cloudflare would cache `public, max-age=…` responses on `/api/shared/*` by default; the architecture reviewer proved otherwise (CF bypasses dynamic paths regardless of Cache-Control), forcing a Terraform `cloudflare_ruleset` to be added inline during review-fix. See `knowledge-base/project/learnings/2026-04-18-cloudflare-default-bypasses-dynamic-paths.md`.
- When a plan bumps `--max-turns` on a `claude-code-action` workflow, it MUST also bump `timeout-minutes` to keep the ratio aligned with peer workflows (median 0.75 min/turn, 0.60 acceptable for data-only tasks). A raised turn budget with an unchanged timeout is a silent failure mode — the agent hits the wall clock before exhausting the turns it was granted. See `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` for the peer ratio table. **Why:** In PR #2536, the initial plan raised bug-fixer max-turns 35 → 55 but kept `timeout-minutes: 30` (0.55 ratio, below the median). The review agent caught it; the follow-up commit bumped timeout to 45 (0.82 ratio).
- When a plan adds a regex over user-controlled input (PII scrubbers, log sanitizers, URL validators, CSV parsers), the Risks section MUST state the **maximum input size reachable by the regex engine** — not just a smoke-test number. If upstream callers can send unbounded input (e.g., Next.js's 1MB default body size, no per-field length cap in a JSON validator), the plan must specify a pre-regex `.slice()` bound and justify it. Smoke-testing a 2000-char string proves nothing about a 1MB pathological input. For UUIDs/IDs, match the **structural shape** (8-4-4-4-12 hex), not a specific version — version-restricted regexes (e.g., v4-only) leak stronger-PII variants (v1 MAC+timestamp) when a caller uses a different generator. Avoid `/g` regex + `.test()` gates; prefer `const next = s.replace(RE, ...); if (next !== s) { fired.push(name); s = next; }` — the `.test()` pattern relies on `.replace()` resetting `lastIndex` and silently leaks on a future edit that removes the `.replace()`. See `knowledge-base/project/learnings/security-issues/2026-04-17-pii-regex-scrubber-three-invariants.md`.
- Do not prescribe exact learning filenames with dates in `tasks.md`. Dates drift across session boundaries. Prescribe directory + topic only (e.g., `knowledge-base/project/learnings/bug-fixes/<topic>.md`) and let the author pick the date at write-time. **Why:** PR #2226 prescribed a `2026-04-14-...` filename but the file was created on the 15th, forcing a tasks.md fix-up.
- When a PR has post-merge operator actions (terraform apply, manual verification, external service setup), split `## Acceptance Criteria` into `### Pre-merge (PR)` and `### Post-merge (operator)` subsections. Flat lists make reviewer check-offs ambiguous. **Why:** PR #2226 P1 review finding.
- **Before authoring any `### Post-merge (operator)` step, run the automation-feasibility gate.** For each candidate step, check whether a loaded MCP server or CLI can execute it:
  - Supabase migration apply / `cron.job` verify / bucket-exists check / RLS spot-check → `mcp__plugin_supabase_supabase__*`
  - `gh pr ready` / `gh pr merge --squash --auto` / `gh issue close` / `gh workflow run` → `gh` CLI via Bash
  - End-to-end UI flow → Playwright MCP (`mcp__playwright__*`)
  - Cloudflare DNS / WAF / Workers / Zero Trust → `mcp__plugin_soleur_cloudflare__*`
  - Stripe live-state read / customer / subscription → `mcp__plugin_soleur_stripe__*`

  If the step is automatable, the plan MUST bake it into the workflow rather than punt to the operator. Three valid placements:
  1. **Inline in a /work phase** (typical for migration apply, integration smoke, single-call MCP/CLI verifications).
  2. **In `/soleur:ship` post-merge verification** (already handles migration verify + `gh pr ready` + auto-merge + `gh workflow run` for modified workflows — see ship/SKILL.md:1027 + 1177).
  3. **In a GitHub Actions workflow** that fires on push to `main` (the `apply-deploy-pipeline-fix.yml` pattern documented in ship/SKILL.md:508 — auto-applies on merge).

  Genuinely operator-only steps (CAPTCHA-gated portal config, interactive OAuth consent on a third-party site, subjective decisions requiring human judgment — design taste, strategy, prioritization) MAY remain in `### Post-merge (operator)` with a one-line `Automation: not feasible because <X>` justification. **Interpretation of technical signal (recovery curves, IOPS budgets, error rates, latency percentiles) does NOT qualify as "human judgment"** — if the data is API-accessible, the plan must prescribe the query + deterministic verdict rule per `hr-no-dashboard-eyeball-pull-data-yourself`, not punt to operator dashboard-watching. Steps that are silent about automation feasibility default to operator-driven and are documentation debt — review-time will reject them. **Why:** every "please run this manually" is a context switch the founder is doing alone (ship/SKILL.md:1027). PR #1375 left migration verification as a "post-merge todo" instead of executing it; deployed code expected the new schema and broke. The plan author is the right place to catch this — by /work-time the agent is committed to the plan as written. Same class as the Playwright-first audit in work Phase 4: if a tool exists, use it.
- For `type: ops-remediation` / `classification: ops-only-prod-write` plans whose fix is executed post-merge (operator runs `terraform apply`, applies a migration, etc.), the Pre-merge acceptance criterion for issue links MUST prescribe `Ref #N` in the PR body, not `Closes #N`. `Closes` auto-closes at merge — before the remediation runs — producing a false-resolved state. The actual issue closure lives in a post-merge step (`gh issue close <N>` after the apply succeeds). Extends `wg-use-closes-n-in-pr-body-not-title-to` for the ops-remediation class. **Why:** PR #2880 — plan line 378 prescribed `Closes #2873 / #2874`, caught inline by multi-agent review.
- Before prescribing a rename of any `AGENTS.md` rule id (`[id: hr-*]`, `[id: wg-*]`, `[id: cq-*]`), grep the whole repo for the old id (`grep -rn '<old-id>' . --exclude-dir=.git`) and update every call site in the same commit. The `cq-rule-ids-are-immutable` rule covers only AGENTS.md itself — downstream references in `.claude/hooks/`, tests, docs, and `.github/workflows/` must be updated manually. **Why:** 2026-04-15 rename broke two test files because the rename was not grep-propagated.
- For any acceptance criterion that cites an external corpus (`gh issue list`, file globs, label queries, etc.), run the exact query before freezing the AC. If the corpus returns zero, either scope the AC out or file a deferral issue in the same commit — don't freeze an AC that depends on a corpus you haven't verified exists. **Why:** PR #2346 golden-set AC deferred via #2352.
- When a plan specifies a fixture seeding N entities, classify each entity as **DB-only** / **external service** / **hybrid** before freezing the spec. External-service entities (files in external repos, OAuth-gated resources, third-party APIs) often need separate seed strategies and may require deferral. **Why:** PR #2346 KB fixture lived in GitHub workspace, not Supabase — deferred via #2351.
- When a plan prescribes `flock -x N ( ... ) N>>"$file"` with a variable reassigned inside the subshell that a later outer command consumes, state explicitly where the assignment lives. Subshell reassignments do NOT propagate — the outer command sees the pre-subshell value. Hoist the assignment outside the `( ... )`, or complete consumption inside. **Why:** PR #2573 initial rotation block reassigned `archive=` inside the flock subshell; the outer `gzip -f "$archive"` targeted a non-existent path and T9 failed until the uniquify block moved out. See `knowledge-base/project/learnings/best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`.
- When a plan prescribes a `SCHEMA_VERSION` constant or any cross-process contract field, it MUST include a task for asserting the value at every consumer boundary — not just on the producer side. A field written but never read is cosmetic; a schema contract is the set of places it is asserted. **Why:** PR #2573 shipped SCHEMA_VERSION as a self-referential check in the aggregator; consumer-side gating was added inline during review when the architecture reviewer flagged the gap.
- When a plan introduces a shell wrapper (`with_lock`, `with_lease`, `flock -- <cmd>`, etc.) around a command intercepted by a PreToolUse hook, the plan MUST grep every hook for the command-detection regex (`grep -nE 'gh\s+pr\s+merge|<cmd>' .claude/hooks/*.sh`) AND propose a regex extension that catches the wrapped form. Hook regexes anchored to `^|&&|\|\||;` (start-of-line / chain operators) silently bypass the hook when the command appears after a `--` separator inside another command's argv. **Why:** PR #3689 wrapped `gh pr merge --auto` in `bash session-state.sh with_lock merge-main 600 -- gh pr merge ...`; the existing `pre-merge-rebase.sh` regex did not match the wrapped form, silently bypassing the review-evidence gate AND the origin/main auto-sync. Caught only at 11-agent post-implementation review. See `knowledge-base/project/learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md` (SE1).
- When a plan says "extract a shared factory/helper for N files" or enumerates a file list scoped from an issue body, validate N at planning time by grepping the distinguishing pattern (`rg '<pattern>' test/ src/`) — never trust the issue's enumerated list. Issue authors typically scan one directory; the real pattern usually spans more. **Why:** PR #2574 plan scoped 7 sidebar test files; review's pattern-recognition agent found 3 more (`chat-page*`, `error-states`) requiring inline scope extension. See `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`.
- When a plan adds a Supabase DDL migration, `ls apps/web-platform/supabase/migrations/` and read the 2-3 most recent files before prescribing DDL constructs. Supabase's migration runner wraps each file in a transaction, so `CREATE INDEX CONCURRENTLY`, `VACUUM`, `ALTER SYSTEM`, and other non-transactional DDL will fail at deploy with SQLSTATE 25001 — sibling migrations typically document the constraint inline. Cite the specific sibling migration that demonstrates the pattern your plan adopts. **Why:** PR #2579 plan prescribed `CREATE INDEX CONCURRENTLY` verbatim from Postgres docs; migrations 025 and 027 had explicit comments rejecting CONCURRENTLY that the deepen-pass didn't read. See `knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md`.
- When a plan prescribes testing a security invariant of an LLM-mediated tool (SDK-invoked sandbox, agent-routed API call, MCP server driven by natural-language input), the test harness MUST remove the LLM from the assertion path. Natural-language prompts (`query({ prompt: "Run this command..." })`) are non-deterministic — the model may introspect, reword, refuse, or emit as text. A green suite proves model compliance, not the security invariant. Prefer: direct tool-invocation entry, captured-argv `child_process.spawn`, or any path that short-circuits the model. **Why:** #1450 plan initially scaffolded `query()`-prompt-based tier-4 bwrap assertions; plan-review caught this before any test shipped. See `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`.
- When a plan adds a source-template drift-guard test (regex/grep over `.njk`, `.hbs`, `.html`, `.jsx`, etc.), the test's file list MUST be a directory walk over the source root — never a hardcoded file list taken from the issue body. Issue authors typically name 1-2 files; the bug class usually spans more. Prescribe `walkDir(resolve(REPO_ROOT, "<source-root>"))` plus a sanity assertion that the walk found ≥ N known templates. **Why:** #2609 plan scoped the drift-guard to `base.njk` + `blog-post.njk`; review found 9 other `.njk` files with the same bug pattern (`<script type="application/ld+json">` interpolations), widening required inline during review. See `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`.
- When a plan prescribes HTML-escape-aware fixes inside `<script>` blocks (JSON-LD, inline config, hydration blobs), `JSON.stringify` / Nunjucks `dump` / similar JSON-serializers are necessary but not sufficient. The plan's Risks section MUST enumerate three hazard classes: (1) JSON parse failure (raw `"` / control chars), (2) HTML tag breakout (`</script>` / `</SCRIPT>` closes the outer tag), (3) JS runtime string termination (U+2028 / U+2029 in legacy runtimes). Prescribe a dedicated filter that applies all three escapes (`</` → `<\/`, `\u2028`, `\u2029`) rather than raw `dump`/`stringify`. **Why:** #2609 initial plan chose `| dump | safe` which left `</script>` breakout live for any attacker-controlled frontmatter field; review forced a `jsonLdSafe` filter inline. See the same learning file.
- When a plan adds a new skill OR a new AGENTS.md rule, the Acceptance Criteria section MUST include the measured **current** budget headroom so the work phase knows how much room it has, not just the cap. For skills: run `bun test plugins/soleur/test/components.test.ts` at plan time and note `current/1800` words; prescribe the new description ≤ `1800 - current` words. For AGENTS.md rules: run `awk '/<rule-id>/ {print length($0)}' AGENTS.md` during drafting (not after), and verify the count with a grep of the new rule's byte length. **Why:** PR #2683 — initial skill description was 43 words over a 1799-word baseline (required trimming three sibling skills); initial AGENTS.md rule was 687 bytes over the 600-byte cap (required two trim iterations). See `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` session errors.
<!-- mirror: deepen-plan/SKILL.md loader-class-fit bullet — keep in sync; trim both together -->
- When a plan proposes any AGENTS.md `core→rest` demotion (`wg-*` only — `hr-*` may not be demoted per CPO sign-off PR #3496 condition 3), verify **loader-class fit** before freezing the demotion: `sed -n '88,115p' .claude/hooks/session-rules-loader.sh` to read the `DOCS_RE`/`CODE_RE`/`INFRA_RE` regex block AND the class-selection branch (`docs-only` fires when `HAS_DOCS=1 && HAS_CODE=0 && HAS_INFRA=0` → loads `core+docs-only` only; `code` or `infra` triggers `core+rest`). For each demotion candidate, classify its trigger surface: does it fire on plan/learning/spec edits (docs-only), or only on code/infra? If `docs-only` is in the trigger surface but `AGENTS.rest.md` does NOT load on docs-only, KEEP in core (body-trim instead). Cite the `sed` output + the class-fit determination in the plan body. **Why:** PR #3681 — `wg-plan-prescribed-skills-must-run-inline` was demoted core→rest before pattern-recognition reviewer caught the gap; `/work` runs on docs-only PRs and `AGENTS.rest.md` does not load there. See `knowledge-base/project/learnings/2026-05-12-agents-md-trim-loader-class-fit-verification.md` (lands with #3681).
- When a plan paraphrases an issue body's file-path or site-count claims, `ls`/`Read` every path and grep every symbol the body names BEFORE writing the plan — not during deepen-plan. Paraphrase-without-verification is the single most common plan-drift class (wrong MCP file path, stale duplicate-site count, inverted test assertion). Run `rg '^function <symbol>\b' <dir>` for every distinguishing symbol in the issue body and add a §Research Reconciliation table if any divergence is found. **Why:** PR #2817 — three separate stale claims in the plan (MCP file at `lib/mcp/` vs `server/`, 4 createQueryBuilder sites vs 3, inverted test assertion shape) all caught at deepen-plan and resolved inline; moving the grep gate into Phase 1 would have caught them at the cheapest point. See `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`.
- When a plan scopes "agent-native parity" or MCP tool parity with a UI feature, enumerate the UI hook's exported surface (`grep -E "^\s*(const|function|async function)" <hook-file>`) and map EVERY function to a tool or explicit deferral — don't trust the issue body's enumeration. Common miss: list/filter/archive/unarchive named; status-update or delete omitted. **Why:** PR #2817 plan scoped `conversations_list` + archive/unarchive but omitted `conversation_update_status` (the Command Center's most common action); agent-native-reviewer caught it at review and the tool had to be added inline. See same learning file.
- When a plan prescribes pre-merge verification of a **new** CI workflow via `workflow_dispatch`, flag it as infeasible — GitHub requires the workflow file to exist on the **default branch** before `gh workflow run <file>.yml --ref <feature-branch>` can dispatch it (returns `HTTP 404: workflow not found on the default branch`). For pre-merge verification of a new workflow or composite action, choose one of: (1) wire the check as a job in an existing `pull_request`-triggered workflow so it runs on PR events against the feature branch, (2) extract the logic into a shell script / module that is locally testable with mocked inputs, or (3) explicitly defer verification to post-merge `gh workflow run <existing-workflow>.yml`. Never plan "add a temporary test workflow with `workflow_dispatch`, trigger from the feature branch, delete before merge" — step 2 is impossible and the plan's mock-code-path in production will become dead-code + insider-bypass surface when the unreachable test is removed. **Why:** PR #2717 — see `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`.
- When a plan adopts a centralizing helper / boundary / redaction layer for a PII or security transform, every AC's verification command (grep, lint, regex gate) AND every disclosure-language claim (PA8, privacy policy, security overview) MUST scope to the SPECIFIC boundary the transform covers — not the abstract category. "No raw userId in `extra`/`tags` anywhere in `apps/*/server/`" over-matches once the helper accepts raw userId by design; "pseudonymized at the emit boundary" over-claims once only the helper-routed emit paths carry the transform. The two-clause form is the only form that survives the centralization choice: (i) helper-routed sites verified via grep over helper output, (ii) direct-bypass sites verified via grep restricted to sites that do NOT route through the helper. **Why:** PR #3685 (#3638 Sentry userId hash) plan AC2 stipulated a grep gate that returned ~40 helper-invocation matches at /work verification time; PA8 §(c) overclaimed pseudonymization scope across ~27 pre-existing direct-log sites caught only by multi-agent cross-reconcile. See `knowledge-base/project/learnings/2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`.
- When a plan prescribes an **aggregate numeric target** in Acceptance Criteria (bytes saved, rules removed, perf delta, coverage %), the plan body MUST show the per-item contributions that sum to the target. If per-item estimates sum to a number that disagrees with the aggregate, the aggregate is wrong — fix it at plan time, don't leave the mismatch to be negotiated at work time via spec strikethrough+replacement. Plan-review agents (code-simplicity + architecture-strategist) do not check numeric self-consistency by default; the plan author owns this. **Why:** PR #2754 — plan prescribed "≥800 bytes saved" while its own per-rule byte-impact table projected only ~260 bytes; actual outcome was +21 bytes, forcing a spec FR4 relaxation mid-implementation. See `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`.
- When a plan AC claims the state of an external-service config (Doppler values, Supabase rows, Cloudflare applied state, GitHub secret presence, Stripe product config), verify via the actual API at plan time — code-grep confirms consumers exist, NOT that the config holds values. These are different questions, and plan-review agents cannot detect the conflation without making the API call themselves. Generalizes beyond Doppler. **Why:** PR #2769 — plan AC claimed "dev Doppler has all 6 NEXT_PUBLIC_* secrets; confirmed by codebase audit" but dev was missing 3 keys; AC had to be rewritten at work-phase. See `knowledge-base/project/learnings/best-practices/2026-04-22-plan-ac-external-state-must-be-api-verified.md`.
- When a plan prescribes extension of a tool-tier / permission / registry map (e.g., `TOOL_TIER_MAP`, `ROUTABLE_DOMAIN_LEADERS`, `WORKFLOW_HANDLERS`), grep the map's current entries to verify scope before adding. Maps are usually scoped to one tool family by prefix or class — entries outside the scope are dead code and create false safety. **Why:** PR #2858 (#2853 plan) — Stage 2.7 extended `TOOL_TIER_MAP` (scoped to `mcp__soleur_platform__*`) for SDK-native tools; permission gating for those flows through `permission-callback.ts` directly. Caught by deepen-pass. See `knowledge-base/project/learnings/best-practices/2026-04-23-plan-quality-class-deepen-pass-catches.md`.
- When a plan prescribes an aggregate cost SLO for a skill-mediated routing change, sum the per-skill baseline (subagent fan-out × per-leader cost) before fixing the cap. Brainstorm Phase 0.5 spawns 4+ leaders at $0.05-$0.15 each = $0.20-$0.60 floor; aggregating without this baseline produces a cap that fires constantly. Split per-workflow when costs span an order of magnitude. **Why:** same learning file — PR #2858 plan proposed P95 ≤ $1 conversation cost; realistic brainstorm $1.50-$3.50; fix split into `$0.50` one-shot/work, `$2.50` brainstorm/plan.
- When a plan widens a discriminated union with a `kind`-typed polymorphic payload, design the per-variant payload sub-union in the plan, NOT deferred to implementation. A `payload: ...` placeholder lands as `unknown` and creates one cast-site per variant. Specify per-`kind` typed payloads explicitly (and per-`kind` response shapes if there's a request/response pattern). **Why:** same learning file — PR #2858 plan deferred `interactive_prompt.payload` sub-discrimination; type-design-analyzer flagged it as the highest-risk type gap; rewrite added 6 typed payload variants + 6 typed responses inline.
- When a plan proposes a sentinel value in a DB column (magic string like `'__unrouted__'`, `'pending'`, `'__unset__'`), grep 2-3 recent migrations for the codebase's discriminator convention before specifying. Most codebases use NULL with partial indexes OR explicit boolean OR proper enum — magic strings in free-text columns conflate two facts (presence + value) and break grep tooling. If a sentinel is unavoidable, wrap as a TS ADT at the storage boundary so the magic string never leaks past persistence. **Why:** same learning file — PR #2858 plan used `'__unrouted__'` in `active_workflow text`; codebase pattern is NULL + partial indexes (5+ migrations); architecture-strategist + type-design-analyzer both flagged.
- When a plan **relaxes or removes** a load-bearing defense (timeout, retry budget, rate limit, validator gate, byte cap, ceiling), enumerate every threat surface the original defense was bounding — including side-effect roles the defense was incidentally serving. For each, name the new defense or document why none is needed. "Same defense at a more permissive value" is acceptable; "same defense with a different reset/scope semantic" silently dissolves any side-effect roles and needs a new explicit ceiling. **Why:** PR #3225 — plan raised `DEFAULT_WALL_CLOCK_TRIGGER_MS` 30s→90s AND changed reset semantic to "every assistant block". The 30s ceiling was bounding two threats: idle-window AND absolute turn duration. The new semantic dissolved the second role (a chatty agent emitting one block every <90s never trips runaway), caught only at multi-agent review (architecture-strategist P1). Recovery added `DEFAULT_MAX_TURN_DURATION_MS = 10 min` as a separate non-resetting ceiling. See `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
- When a plan adds new operator-facing WebSocket events (especially client→server `*_response` style for interactive prompts), check whether each new event has an MCP tool counterpart, or file a V2 tracking issue per missing tool. Anything an operator can do via the chat UI's interactive prompt should be doable by an agent via MCP tool — agent-user parity covers WS event surfaces, not just UI hook surfaces. **Why:** same learning file — PR #2858 plan added 6 new client→server `interactive_prompt_response` variants with zero MCP tool counterparts; agent-native-reviewer caught it; resolved by filing 5 V2 tracking issues.
- When a plan prescribes a validator, guard, linter, or linter rule that rejects a pattern, include a plan-time grep counting current matches on the protected surface. If non-zero, Acceptance Criteria MUST cover grandfathering or retroactive remediation — "future-only enforcement" is a false framing when the surface already contains matches. The forward-looking sibling of "paraphrase-without-verification": plans also must not assert forward claims about a protected surface without running the guard's reject-criteria against current data. **Why:** PR #2877 — plan asserted "no hr-* currently retired" without grepping `retired-rule-ids.txt`; two hr-* from PR #2865 surfaced at GREEN and forced an inline `HR_RETIREMENT_ALLOWLIST` pivot. See `knowledge-base/project/learnings/2026-04-24-guard-surface-audit-before-coding.md`.
- When a plan binds an SDK/runtime call that needs async per-user fetches (BYOK key, service tokens, workspace path, etc.) behind an existing **synchronous** factory/builder contract (`(args) => T`), the plan MUST prescribe widening the contract to `(args) => Promise<T> | T` rather than wrapping async work in a deferred-construction proxy. Sync-contract proxies that lazily resolve at first iterator/method call silently move errors out of the original try/catch's observability scope (Sentry tags, error-code mappings, runtime invariants tied to the boundary) into a downstream consumer that wasn't designed to handle them. The runner's `await` inside its existing try/catch tags both sync and async errors uniformly; sync callers keep returning a resolved Promise. **Why:** PR #2901 (Stage 2.12 cc-soleur-go) — work shipped a 200-LoC Query proxy because the plan didn't anticipate the `QueryFactory = (args) => Query` collision with async credential fetches; 4 review agents flagged it (AC14/R10 regression: `KeyInvalidError` no longer mapped to `errorCode: "key_invalid"`). Fix-inline widened the type and deleted the proxy. See `knowledge-base/project/learnings/best-practices/2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md`.
- When a plan changes Eleventy `permalink:` frontmatter, output filenames, or any `_data/permalink.js`-controlled path scheme, prescribe a `git grep -F "<old-path-token>" .github/workflows/` sweep AS PART OF THE PLAN (not deferred to implementation review) and update every match in the same PR. The `Verify build output`-style step often `test -f`s the old path; if Eleventy emits redirect stubs at the legacy path, the gate will pass silently while the canonical path is broken. Also flag any unguarded `test -f _site/<old-pattern>` in the plan's verification checklist. **Why:** PR #1851 restructured permalinks but left `deploy-docs.yml`'s `test -f _site/pages/${page}.html` loop untouched; the gate passed silently for 18 days because redirect stubs at the legacy paths kept `test -f` happy. See `knowledge-base/project/learnings/best-practices/2026-04-28-learning-sharp-edges-need-tracking-issues-not-memory.md`.
- When a plan prescribes `dig`, `nslookup`, `curl`, or any network call inside a CI step, pin a timeout (`dig +time=N +tries=M`, `curl --max-time N`, etc.). Unbounded network calls inherit resolver/socket defaults and can hang for tens of seconds on flake, blowing CI wall-clock without a clear failure signal. **Why:** PR #3007 — plan prescribed `dig +short CNAME` for custom-domain ref derivation; review caught the unbounded wall-clock risk. See `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` session error 1.
- When a plan prescribes echoing JSON-decoded values (jq output, base64-decoded payloads, untrusted claim values) into GitHub Actions annotations (`::error::`, `::notice::`, `::warning::`), prescribe a CR/LF strip via `${var//[$'\n\r']/}` BEFORE the echo. Annotations are line-oriented; a `\n::notice::PASS` smuggled into a `.iss` claim could spoof success. **Why:** PR #3007 — security-sentinel flagged log-injection vector via crafted JWT claims; resolved inline via `iss_safe`/`role_safe`/`ref_safe` sanitization. See same learning file, session error 6.
- When a plan documents a workaround for a closed upstream issue, verify the failing-code-path mechanism against the **installed** library source (`node_modules/<pkg>/.../*.js`), not just the upstream issue's prose. Major-version churn between issue-close and the version actually installed can swap the failing code path (e.g., a `ws`-fallback race in v2.87 that was replaced by an `unsupported`-throw in v2.88+) while preserving the same end-symptom. The right-shape workaround at runtime can still be the same line; the mechanism explanation in the learning file is what drifts and rots. **Why:** PR #3058 — initial draft of the supabase-js Phoenix-JOIN learning encoded the upstream-issue mechanism, but installed `@supabase/realtime-js@2.99.2` returns `{ type: 'unsupported' }` rather than falling back to `ws`. git-history-analyzer caught the drift between upstream-issue prose and installed code. See `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md`.
- When a plan's Acceptance Criteria prescribes a verification grep for a CLI-form-bug class (fabricated flag, wrong stdin sentinel, `echo`-vs-`printf` newline, `< /dev/stdin` no-op), default the grep scope to ALL operator-facing surfaces — `knowledge-base/engineering/`, `knowledge-base/project/learnings/`, `.github/`, `apps/*/docs/`, root `README.md`/`CONTRIBUTING.md` — and exclude only `knowledge-base/project/{plans,specs}/**` and `**/archive/**` (which preserve historical record). Narrow scopes that target only the named file's directory miss same-class bugs in adjacent operator-facing surfaces. **Why:** PR #3059 — plan AC1 was scoped to `knowledge-base/project/learnings/` and missed three same-class bugs in runbooks (`oauth-probe-failure.md`, `dashboard-error-postmortem.md`) and a workflow issue-body template (`scheduled-linkedin-token-check.yml`). Multi-agent review caught all three; cosign-DISSENT correctly flipped them from scope-out to fix-inline. See `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`.
- When a plan asserts behavior of a third-party GitHub Action ("action X auto-configures Y", "Y is auto-injected by Z", "Z handles W internally"), grep the same repo's `.github/workflows/` for prior usage of the action and reconcile the claim against codebase precedent in the SAME plan step that asserts it. Plan-time research is good at "what does X claim" (docs, manifests); it is bad at "what does the surrounding workflow actually do to make X work reliably" — that lives only in working precedent. **Why:** PR #3155 — plan asserted `claude-code-action@v1` auto-configures `git config user.name/email`; all 10 sibling Soleur `scheduled-*.yml` workflows actually run an explicit `git config` step before pushing. Architecture-strategist caught it at multi-agent review as a P1; without the fix, `git commit` aborts with "Author identity unknown" at fire time — the exact regression the plan was designed to fix. See `knowledge-base/project/learnings/best-practices/2026-05-04-verify-third-party-action-behavior-claims-against-codebase-precedent.md`.
- When a plan prescribes inline JWT minting (RS256 + openssl) for a CI workflow that calls `gh api` with App-JWT auth, three silent-failure traps must be addressed in the plan body, not deferred to /work: (a) `gh api` does NOT accept JWT-format `GH_TOKEN` (sends `token`, not `Bearer`) — use curl with `--header @<(printf ...)`; (b) `openssl base64 -A` trails a newline that `tr -d '='` does NOT strip — use `base64 -w 0 \| tr '+/' '-_' \| tr -d '=\n'`; (c) `if: failure()` does NOT fire when the previous step has `continue-on-error: true` — use `if: steps.<id>.outcome == 'failure'`. See `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md`. **Why:** PR #3187 plan-review caught all three pre-merge.
- When a plan adds a defensive guard at a chosen call-site (validator, normalizer, prefill check, rate limiter), trace the value-of-interest from the entry point (WS frame, route handler, queue worker, cron tick) all the way to the guard's input — NOT just from the guard outward. Internal threading (`runner.dispatch({sessionId}) → factory(args.sessionId) → guard`) verifies the guard's correctness GIVEN an input; the upstream trace verifies the input ever exists. Add a §Research Reconciliation row that names every frame the value passes through and the line where each frame forwards or drops it. **Why:** PR #3263 — guard placed in `realSdkQueryFactory` based on runner-internal threading; ws-handler's `dispatchSoleurGoForConversation` discards `conversations.session_id` between the SELECT (line 1138) and the dispatch (line 620), so `args.resumeSessionId` reaches the guard as `undefined` on every cold start. Multi-agent review (data-integrity-guardian + architecture-strategist) caught the dormancy; recovery extracted the guard to a shared helper called from both the cc-soleur-go path AND the legacy `startAgentSession` (the actual production trigger). See `knowledge-base/project/learnings/best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`.
- When a plan prescribes a Sentry-telemetry threshold as a deferral gate ("if Sentry shows ≥N hits over T days, fold in; else defer"), verify the search query actually matches a known-recent error of the same class before treating zero hits as absence. Anthropic SDK errors land as `Error: Claude Code returned an error result: …` titles without the request body, so substring searches on `prefill`, `claude-sonnet-4-6`, or `invalid_request_error` return zero — the wrapper title swallows the body. Run a representative substring-broadening sweep (error-class wrappers, stripped-status-code variants) AND confirm at least one matching event exists for any known recent error before relying on the gate. **Why:** PR #3263 Phase 3 audit returned 0 hits against 680 baseline for `prefill`/`claude-sonnet-4-6`/`invalid_request_error`; broader query (`anthropic OR claude OR APIError`) confirmed the original was too narrow. The architectural-fact path (shared model + shared resume threading on legacy) overrode the empirical zero, but the gate should not have been declared "satisfied" on the original query. See same learning file.
- When a plan adds an application-layer recovery primitive (TS guard, sync reaper, retry envelope) that mirrors a SQL-layer or scheduler-layer primitive at the **same threshold** (same `< now() - X` predicate, same retry budget, same staleness window), the plan body MUST name which sub-value the application-layer copy is load-bearing for: (a) cross-layer state truing that the SQL/scheduler primitive doesn't perform (e.g., flipping a related row's status), (b) observability the SQL/scheduler primitive doesn't emit (Sentry, structured logs), or (c) drift-resilience if the SQL/scheduler primitive is later refactored. If NONE of (a)/(b)/(c) applies, either tighten the application-layer threshold so it catches what the SQL/scheduler misses (and pay the defense-relaxation analysis cost per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`) or drop the application-layer copy entirely. Plan-time domain-review CTO probe: "Does this new code path mirror a predicate that already exists in another layer? If yes, name the load-bearing sub-value." Architecture-strategist at PR-review time is too late — by then the contested-design alternatives are filed as follow-ups instead of debated in the plan. **Why:** PR #3354 — plan widened `tryLedgerDivergenceRecovery` with a stale-heartbeat SELECT at 120 s threshold, identical to migration 029's lazy-sweep predicate inside the same RPC's transaction. Architecture review surfaced the redundancy and named three alternatives (tighten / drop / keep-as-defense-in-depth); filed scope-out #3372 because each alternative carried non-trivial trade-offs. The branch's actual sub-values (status-flip + Sentry + drift-resilience) were never explicit in the plan. See `knowledge-base/project/learnings/2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value.md`.
- When a plan changes a `MAX_*_SIZE` / `*_CAP_BYTES` / `MAX_*_LENGTH` constant (or any byte/length ceiling on uploaded/persisted artifacts), grep ALL readers of the affected artifact class — not just call sites of the constant being changed. Reader-side caps are typically *literal* (hand-rolled `15 * 1024 * 1024`), not imported, so a callers-of-constant grep returns zero and looks safe while a sibling reader silently gates in the band between the old and new caps. Run `git ls-files | grep -E "<artifact-pattern>"` (e.g., `pdf|attachment|image`) and `rg "\* 1024 \* 1024" <reader-paths>` to find unaligned literals; require imports of the shared constant (or scope-out + tracking issue) for every match. **Why:** PR #3353 — #3337 raised the PDF upload cap to 24 MB; #3338 (cut before #3337 merged) introduced the extractor with a 15 MB literal that nobody could see was misaligned without a cross-PR audit. Surfaced only via Sentry event `9e0a3888fd3849cd87cb83cdcecca199` after a real user tripped the [15, 24] MB band. See `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md`.
- When prescribing GitHub labels in Acceptance Criteria (e.g., for tracking issues created post-merge), verify each label exists via `gh label list --limit 200 | grep -E "^<label>\b"` BEFORE writing the AC. If a label doesn't exist, either substitute the closest existing label (with a note in the AC) or add a Phase 0 step to `gh label create` it. The verify-before-cite convention also lives in `deepen-plan/SKILL.md` Phase 4 AC and in `/soleur:drain-labeled-backlog`'s validator step. **Why:** PR #3378 — plan prescribed `infrastructure` and `seo` labels that didn't exist; substituted with `domain/engineering`, `chore`, `priority/p3-low` at issue-creation time. See `knowledge-base/project/learnings/2026-05-06-plan-prescribed-labels-must-be-verified.md`.
- When a plan splits a feature into a foundations PR + downstream wiring PR(s), label each foundations-PR surface as **inert** (no production caller — router modules with no callers, devDeps with no imports, types with no consumers) or **contract-declaring** (system-prompt directives, schema fields a downstream PR is meant to consume, observability events, behavior changes already-shipped resolvers/dispatchers will route into the new branch). Contract-declaring surfaces in a foundations PR require atomic delivery with the wiring PR, a default-closed feature flag, or fall-through to existing safe behavior — never ship the contract ahead of delivery, even when the surface "feels safe as foundations." **Why:** PR #3440 (Phase 3.A) shipped a chapter-chunked system-prompt directive declaring a `document` content-block contract whose dispatch-time attachment lived in #3472 (Phase 3.B); multi-agent review (architecture-strategist + data-integrity-guardian + user-impact-reviewer) converged on the directive-without-delivery state as a `single-user incident` brand-survival regression and forced a runner fall-through to the existing `too_many_pages` bridge. See `knowledge-base/project/learnings/2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`.
- When a plan widens a TypeScript discriminated union (`WSMessage`, `ChatMessage`, etc.), do NOT prescribe an exhaustiveness-site count or a fixed file:line list. Source-grep undercounts: `_exhaustive: never` rails live in test-only `*.test-d.ts` gates and in adjacent server/handler switches that scopes like `{lib,server,components}/` miss. Prescribe instead "run `tsc --noEmit` after the union edit; every TS2322 'X is not assignable to never' is a rail to widen". The compiler is the canonical enumerator; counts in plans drift. **Why:** PR #3419 — plan prescribed 4 sites; actual was 5 over `WSMessage` + 2 over `ChatMessage`; deepened plan still missed `ws-handler.ts:1640` and `chat-message-exhaustiveness.test-d.ts:38`, surfaced only by `tsc --noEmit` at Phase 6. See `knowledge-base/project/learnings/2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`.
- When a plan proposes a fix to a flaky negative-substring assertion over output that embeds RNG-derived strings (`randomUUID()`, `nanoid()`, `Math.random().toString(36)`), enumerate the RNG's emitted alphabet (`randomUUID()` v4 → `[0-9a-f]`, `nanoid` default → `[A-Za-z0-9_-]`, `Math.random().toString(36)` → `[0-9a-z]`) and weigh at least one **data-side fix** (rename the fixture literal to a character outside that alphabet) ahead of any **assertion-side fix** (word-boundary regex, line-anchored regex, deterministic-RNG spy). Data-side fixes are collision-proof by construction with zero regex-semantics to audit; assertion-side fixes carry residual template-shape risk. **Why:** PR #3615 — plan adopted the issue body's proposed `/\bb\.png\b/` regex and produced a 320-line analysis (truth-table + probability math + deferred-spy follow-up issue) for a flake on a fixture filename. Multi-agent review's code-simplicity-reviewer (1 of 11) surfaced that renaming the fixture from `b.png` to `z.png` was strictly simpler: UUIDs are hex-only, no suffix can end in `z`, original `toContain("z.png")` becomes collision-proof. Net diff dropped from 341/-1 to 3/-3; deferred follow-up #3617 closed as wontfix. See `knowledge-base/project/learnings/2026-05-11-rename-fixture-beats-regex-for-rng-substring-flake.md`.
- When a plan AC uses `diff <(awk '/^heading/,/^delimiter$/' ...)` (region-replacement diff against canonical), enumerate **every paragraph the awk range captures** in the edit instructions — not just the named section's heading + body. Awk ranges greedily include trailing/leading paragraphs that semantically belong to neighboring sections but physically sit inside the range. AC region MUST equal edit-instruction region; otherwise the AC detects drift the implementation cannot fix without scope expansion. Two alignments: tighten the AC range to a tighter delimiter (`<!-- End: ... -->` instead of `^---$`), or expand the edit instructions to cover everything inside the range. **Why:** PR #3669 — plan prescribed "replace GDPR §3.8 heading + body lines 104-107" but the AC's awk range `/^### 3\.8/,/^---$/` also captured the §3.7 balancing-test paragraph that canonical relocated post-§3.8; required a follow-up paragraph relocation at /work time. See `knowledge-base/project/learnings/2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`.
- When a plan AC greps for a date string spanning hero + body Last-Updated lines on Eleventy mirror legal docs, tolerate both punctuation forms in the regex (`Last Updated[: *]+May 12, 2026`) or split into two separate count assertions per location. Hero uses `<p>... Last Updated May 12, 2026</p>` (no colon), body uses `**Last Updated:** May 12, 2026` (with `:**`); a literal `'Last Updated May 12, 2026'` regex matches only the hero. **Why:** PR #3669 — plan AC9 prescribed `grep -cE 'Last Updated May 12, 2026' ... returns 2,2,2` but the body form is unmatchable as-written; recovery required trusting the AC's spirit via a separate `grep -n 'Last Updated'` call. See same learning file.
- For drift-remediation runbooks targeting `apps/web-platform/infra/` via Doppler `prd_terraform`, prescribe the canonical invocation triplet verbatim — never just `doppler run -- terraform plan/apply`. The triplet: (1) `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)` + same for `AWS_SECRET_ACCESS_KEY` (R2 backend creds, must be raw — `tf-var` would mangle them to `TF_VAR_aws_*` and the S3 backend silently fails to authenticate), (2) `terraform init -input=false`, (3) `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform <plan|apply>`. Without `--name-transformer tf-var`, `terraform plan` errors immediately with ~13 `No value for required variable` failures (`cf_api_token_*`, `cf_zone_id`, `cf_account_id`, `webhook_deploy_secret`, `doppler_token`, `cf_notification_email`, `resend_api_key`, etc.). **Why:** #3371 plan cited the precedent (#3061 runbook) but copy-pasted only the `prd_terraform` config name, not the flag or the AWS exports — Phase 1 plan crashed at the keyboard. See `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.
- For drift-remediation plans whose Acceptance Criteria asserts an exact `Plan: N to add, M to change, K to destroy` line copied from a drift-detector snapshot, re-run `terraform plan` against live state immediately before publishing the runbook. Drift snapshots are read-only artifacts captured on the `0 6,18 * * *` cron — up to 12h stale on a fast author, days stale when triage runs after the auto-filed issue. If the live plan diverges from the snapshot at publish time, either (a) the drift was already applied — skip the runbook, verify with curl/file-hash/systemd-unit, close the parent issue; or (b) unrelated drift accumulated — file a follow-up issue and keep scope narrow per `hr-menu-option-ack-not-prod-write-auth`. **Why:** #3371 plan referenced a 2026-05-06 19:48 UTC snapshot for a 2026-05-09 runbook; by apply-time the original target was already in state and 2 unrelated drifts had accumulated; Phase 1 had to be re-scoped at execution. See `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.
- For retirement-cleanup plans (sweeps that drop a retired/fabricated AGENTS.md rule-ID citation from operator-facing files), the AC verification grep MUST scan the full class on the edited files, not just the named target ID. Two greps: (a) every retired ID from the retired-rule registry at the repo root against each edited file, and (b) every rule-ID-shaped token (`\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b`) that does not resolve to an active `[id: ...]` in AGENTS.md. Named-target-only greps return false-pass for the class — the same files often contain other retired or fabricated citations the issue body never enumerated. **Why:** PR #3491 — plan AC verified only the 5 named retired IDs; multi-agent review caught 5 additional retired/fabricated active citations in the same edited files (3 in files the PR was already modifying, 1 fabricated in this skill itself). See `knowledge-base/project/learnings/2026-05-09-retirement-cleanup-grep-must-scan-full-class-not-named-id.md`.
- When a plan prescribes BOTH a contract-changing edit (function return-code semantics, signature change, schema field, env-var contract) AND a contract-consumer edit (consumer of the new return code, new arg, new field), the contract-changing phase MUST come BEFORE the consumer phase — even when the entire PR is single-merge atomic. Plans are read sequentially during `/work`; out-of-order phases produce dead code or fail tests in the consumer phase before the contract phase has shipped. Atomic merge ≠ atomic per-phase TDD. The natural temptation is to group phases by file (consumers + infrastructure) instead of by dependency direction; resist. **Why:** #3509 plan-review — initial draft put hook emission (Phase 2) ahead of the `rotate_if_needed` return-code change (Phase 3); Kieran-rails-reviewer caught it. The Phase 2 `if ! rotate_if_needed` wrapper would have been dead code at Phase 2 boundary. See `knowledge-base/project/learnings/2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.
- When a plan's Acceptance Criteria prescribes a syntax check on a YAML file with embedded shell (GitHub Actions composite action, workflow `run:` blocks), prescribe `yamllint`/`actionlint` for the YAML AND `bash -c '<extracted snippet>'` for the shell — never `bash -n <file.yml>`. `bash -n` parses the entire file as bash and fails at the YAML header (e.g., `description: >`), producing a confusing error that masks the actual verification intent. **Why:** PR #3543 plan AC §111 prescribed `bash -n .github/actions/bot-pr-with-synthetic-checks/action.yml`; implementation hit a YAML-as-bash parse error and had to pivot to `bash -c '<for-loop snippet>'` for the embedded-shell check. See `knowledge-base/project/learnings/2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`.
- When a plan AC prescribes a git command to enforce a per-file co-change invariant (e.g., "files A and B must be touched in the same commit"), the prescribed command MUST be tested against the failure mode it is designed to catch. `git log -- A B` and `git log --oneline -- A B` are UNION filters (commits touching A OR B) — they do NOT distinguish a commit touching only A from a paired commit, and silently green-light the asymmetric-commit failure the AC was designed to catch. For per-commit intersection semantics, walk commits with `git rev-list <base>..HEAD -- <paths>` then `git show <sha> -- <paths>` and grep the diff for both region markers. Sanity-test by constructing three throwaway commits — A only, B only, both — and confirming the prescribed command rejects the asymmetric two. **Why:** 2026-05-11 PR #3550 plan-review (Kieran P1-A + Architecture P1.1) — plan AC #18 prescribed `git log --oneline -- soleur-go-runner.ts agent-runner.ts` as the TR4 single-commit-invariant check; the union semantic would have shipped a green checkmark over the exact `single-user incident` directive-without-delivery failure mode that motivated Phase 3.A's revert. See `knowledge-base/project/learnings/2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`.
- When a plan prescribes reading a field on a cross-module shape (TypeScript interface, Postgres column, GraphQL type, Zod schema, protobuf field, route argument), `rg "<field-name>" <defining-module>` to verify the field exists in the current shape BEFORE freezing the AC or the implementation step. Plan paraphrase often adds plausible-sounding field names ("the resolver already carries path and title") that survive subsection review because each sentence reads coherently — only a grep against the defining module exposes them. If the field is absent, choose ONE of: (a) name the interface-widening edit explicitly in `Files to Edit` and accept the cross-cutting blast radius, (b) thread the value from a closer in-scope source the runner already holds, or (c) drop the dependent AC. Generalizes paraphrase-without-verification (`2026-04-22-ts-sql-normalizer-parity...`) from issue-body paths to cross-module type fields. **Why:** 2026-05-11 PR #3550 plan-review (Kieran P1-B + Architecture P1.3) — plan referenced `documentExtractMeta.path` on `DocumentExtractMeta`, but the resolver shape is `{ numPages?, chapters?, fullExtractedText? }`; AC #13 was unimplementable as written and an unwitting inline interface-widening would have escaped the plan's `Files to Edit` scope. See same learning file.
- When a plan AC prescribes a shell script that captures `git show` (or any multi-KB diff) into a variable and pipes it through `grep -q`, use the tempfile shape (`patch=$(mktemp); git show > "$patch"; grep -c <marker> "$patch"`) instead of `printf '%s' "$diff" | grep -q`. The pipe-from-stdin form interacts with bash pipe buffering + `set -e` short-circuit semantics in ways that vary by shell version; observed failure: grep returned 0 matches against a diff containing 22 occurrences of the marker, both `&&`-chained AND `|| true`-protected forms misfired. Additionally, when an invariant is "no intermediate commit ships only one of two paired markers", make the script track marker **presence at HEAD** (single check, file-based grep on the HEAD-state file) rather than marker **presence in each commit's diff** (per-commit pairing) — the per-commit form false-positives on pure-refinement commits that touch one side without semantic changes to the other, requiring no-op amend-touches to pair markers. **Why:** 2026-05-11 PR #3550 — initial TR4 verification script per plan §3.6 returned `directive=0 dispatch=0` against a commit with 22+8 marker hits; rewriting to tempfile-based grep returned correct counts. Same script flagged the follow-up review-fix commit as FAIL because it refined dispatch wiring without touching the directive marker — required a comment-update amend to pair. See `knowledge-base/project/learnings/2026-05-11-chapter-chunked-dispatch-revival-and-tr4-pure-dispatch-refinement.md`.
- When a plan's Research Reconciliation asserts that a sibling-PR mitigation does NOT apply because the codebase lacks artifact Y (e.g., "no `mx-auto`", "no `ResizeObserver`", "no `onSubmit` handler"), the grep MUST walk the full render tree — route page + layout + shell + components/<feature>/ — not just the layout/shell file the plan was written against. The render tree is wider than the file being edited: a Next.js route page renders INSIDE the shell as `children` and frequently carries the geometric constraints (centering wrappers, fixed-width clamps, scroll containers) that determine whether the mitigation is needed. A single-file grep is insufficient evidence. **Why:** PR #3587 plan asserted KB doc viewer was not `mx-auto`-wrapped (read only `kb-doc-shell.tsx`); the markdown route at `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx:77,153` does use `<div className="mx-auto max-w-3xl">`, and the #3579 anchor-pad mitigation was load-bearing. Pattern-recognition reviewer caught it pre-merge; inline fix landed in c7e70258. See `knowledge-base/project/learnings/2026-05-11-plan-research-reconciliation-must-grep-full-render-tree.md`.
- When a plan prescribes a parsing/extraction pattern (`awk`, `grep`, `jq`, `sed`, `yq`) for frontmatter, config, or any structured-line shape, `git grep` the codebase for the closest precedent at plan-write time and adopt it verbatim — do NOT invent a new form. Bare `awk '/^key:/ {print $2}'` is brittle against quoted values (`key: "value"` prints `"value"`), trailing whitespace, and multi-token values; the canonical robust form is the `gsub` strip used at `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`: `awk '/^key:/ { gsub(/^key:[[:space:]]*"?|"?$/, ""); print; exit }'`. The paraphrase-without-verification rule applies to one's own pattern proposals, not just issue-body claims. **Why:** PR #3625 — plan v1 prescribed brittle `awk '/^lane:/ {print $2; exit}'` in 3 call sites; Kieran P1.2 surfaced the gsub precedent at plan-review time, forcing rewrites. Plan-time grep would have caught it in ~2 minutes vs. ~15-30 minutes at review time. See `knowledge-base/project/learnings/2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md`.
- When a plan adds a schema/config/manifest file (`**/schema.yaml`, `**/*_schema.{yaml,md}`, `**/*.config.{yaml,json}`) to `## Files to Edit`, read the file's first 10 lines for a vendored-upstream header (`# X Documentation Schema`, foreign-domain enum values, sibling `NOTICE` file with `upstream:` frontmatter) AND `git grep -n 'blocking="true"\|validate_required\|enforce: hard'` for the file's consumers BEFORE proposing a new `required: true` field. Adding `required` to a blocking validation gate is a breaking change to ALL existing producers — not just the new category — and editing a vendored-upstream file breaks the sync contract regardless. **Why:** PR #2723 Spec A plan v1 prescribed editing CORA-vendored `compound-capture/schema.yaml`; would have blocked all 13 compound problem_types via the `<validation_gate blocking="true">` at SKILL.md:185. Kieran (P1) caught it by reading the file header; architecture-strategist (P1) caught it by tracing the gate consumer. Both checks are two-line shell at plan-draft time; the cost of catching at /work time is mid-build pivot. See `knowledge-base/project/learnings/2026-05-12-plan-vendored-schema-detection-and-blocking-validation-gate.md`.
- When a plan body quotes a Python `import` statement that points at a path with non-identifier characters (hyphens in the filename, leading digits, embedded dots beyond `.py`), probe the import as a 1-line shell precondition at plan-draft time AND name it as a verification step in /work Phase 1 — never link the prescribed import as the recommended approach without a probe. Python identifiers are `[A-Za-z_][A-Za-z0-9_]*`; `from backfill-frontmatter import …` is a parse error regardless of `sys.path`. The two non-importlib fixes are (a) rename the file to underscores, or (b) extract helpers to a sibling `<name>_lib.py`. Probe form: `python3 -c "import sys; sys.path.insert(0, '<dir>'); from <module> import <name>" 2>&1`. **Why:** PR #2723 Spec A plan v1 prescribed `sys.path.insert(0, 'scripts'); from backfill_frontmatter import …` against the hyphenated migration script `backfill-frontmatter.py` under the repo-root scripts directory; 5-agent plan review missed it; /work hit ModuleNotFoundError at Phase 1 and pivoted to `importlib.util.spec_from_file_location`, then refactored to a sibling `frontmatter_lib.py` after the review pass dissented on the proposed scope-out. See `knowledge-base/project/learnings/2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md`.
- When a plan cites a PR or issue number for provenance of a prior invariant/decision/learning (e.g., "the orphan-suite invariant per PR #X", "deferred per #Y"), `gh pr view <N> --json title` (and/or `gh issue view <N> --json title`) at plan-draft time and confirm the title aligns with the cited semantic role. PR numbers paraphrased from memory or sibling docs are wrong with surprising frequency (PR-vs-issue conflation, mis-keyed sibling PRs, transposed digits); the cost of one `gh` call per citation is trivial vs. propagating wrong provenance into spec/brainstorm/plan and re-discovering it at multi-agent review. **Why:** PR #3672 plan/spec/brainstorm cited "PR #3512/#3533" as orphan-suite-invariant provenance; #3512 was an unrelated cross-sink telemetry PR and #3533 was the *issue* (PR was #3534). git-history-analyzer review caught the drift and required citation-correction edits across 4 docs post-implementation. See `knowledge-base/project/learnings/2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md`.
- When a plan precondition asserts "X is accessible at scope Y", the check MUST grep the producing-scope file for X — not just Read the consuming code. **Cheapest gate:** `grep -nE '\bX\b' <file-that-defines-scope-Y>` against the hook implementation, route handler, or schema definition that produces Y; absence is a precondition failure regardless of how plausible the consuming reference reads. The consuming code can name a variable optimistically (`conversation.created_at` reads as if it's a property of an in-scope object) when the producing scope only exposes `conversationId: string` and a flat hook return; the Read passes while the field doesn't exist at the proposed mount scope. **Why:** PR #3653 — plan §Phase 0.1 asserted `conversation.created_at` accessibility via Read; /work surfaced that `useWebSocket(conversationId)` returns slices without `conversationCreatedAt` and `/api/conversations/:id/messages` did not select the field. Three boundary edits (hook return slice, route SELECT projection, mount-site prop plumbing) required at /work time to thread the value to the component. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.
- When a plan specifies both (a) a component architecture and (b) a parametrized test list (`test.each([healed, postFix, preWindow, streaming, postSunset])(...)`), cross-check at plan time that every test row's fixture input maps to a prop the component actually accepts — symptom shape: "test row references a value the component prop boundary does not expose". If the test list's inputs span predicate state that the architecture pushes outside the component (e.g., predicate lives at the mount site in an IIFE while the component takes only one prop), one of the two must change. Architecture > tests if the tests can be rewritten to drive through a higher-level mount; tests > architecture if the test inputs are the load-bearing brainstorm-owned failure enumeration. The mismatch is invisible to per-section plan review because each section reads coherently in isolation — only the cross-section consistency check catches it. **Why:** PR #3653 — plan §1.1.2 listed 5 test rows needing `messages` + `createdAt` + `isStreamingAssistant` while plan §1.3.2 mount IIFE exposed only `createdAt` to the component; /work pivoted to move the predicate into the component to keep the brainstorm-owned test list verbatim. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.
- When a plan FR conditions on a single enum / union value (`X === "streaming"`, `!isStreamingAssistant`, `status === "completed"`), the FR text MUST classify EVERY union member of `X` as include or exclude. If `X` has N values, the FR must explicitly enumerate all N. Single-value FRs hide a class of bug under any future schema widening, AND the work phase reliably honors the FR verbatim — the gap is structural in the FR, not in execution. **Cheapest gate at plan-write time:** `grep -nE "^export type <Name> =" <module>` to read the current member list, then enumerate each member in the FR with an explicit include/exclude classification. Plan-side complement to hard rule `cq-union-widening-grep-three-patterns` (consumer-side exhaustiveness at union-widening time); together they cover producer (plan) + consumer (code) sides of the same defect class. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; implementation bound it to `streamState === "streaming"`. Codebase: `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`); `"stopping"` is a distinct in-flight substate during mid-aborts that the FR never named. `user-impact-reviewer` caught the slip at PR review only because the review-spawn prompt explicitly enumerated the 3-value enum. Recovery: renamed prop to `isTurnInFlight`, bound to `streamState !== "idle"`. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.
- When a plan FR/AC names a specific third-party API endpoint, query parameter, HTTP verb, or filter shape (e.g., `DELETE /api/0/.../issues/?query=tag:val`, `events.list?filter=Y`), verify the **contract** at plan-write time via WebFetch of the canonical docs URL, OpenAPI/Swagger grep, or sandbox curl — NOT just `gh secret list` / `doppler secrets get` state checks (the existing `2026-04-22-...-external-state-must-be-api-verified` rule covers state; contract is a separate axis). For **pipeline-shape claims** (logs → X, metrics → Y, events → Z), grep the dependency manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `Gemfile.lock`) for the actual transport package (`pino-better-stack`, `@logtail/*`, `dd-trace`, etc.) — sub-processor disclosure ≠ runtime data flow. For **centralization plans** that route an emit through a single helper (`reportSilentFallback`, `mirrorP0Deduped`), require a two-grep verification pattern: helper-centric (`rg "helperName\("`) AND bypass (`rg "underlyingApi\(" | grep -v helperFile`) — helper-centric alone misses direct callers that defeat the centralization. **AC-emit-gate regex**: anchor on the container shape (`(extra|tags):\s*\{[^}]*\bField\b`) not the literal-colon form (`Field:`), which misses shorthand object literals (`{ Field }`). **Why:** #3638 — brainstorm CTO claimed Sentry single-call `DELETE-by-tag` worked (docs misread — actual endpoint accepts only `id=N` list); brainstorm assumed `pino → Better Stack` pipeline (package.json showed no transport, Better Stack is uptime-only on `/health`); plan v1 missed `warnSilentFallback` + 2 direct `Sentry.captureMessage` sites in `ws-handler.ts:693, 719` because grep was scoped to the helper file. All three caught at plan-review by Kieran. See `knowledge-base/project/learnings/2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md`.

NEVER CODE! Just research and write the plan.
