---
name: plan
description: "This skill should be used when transforming feature descriptions into well-structured project plans following conventions."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

<!-- plan-anti-bypass-protocol:start -->
## Anti-bypass protocol (load-bearing — especially Grok Build)

You are the **planning orchestrator**. Whether entered from `soleur:brainstorm`, `soleur:one-shot` Step 1, or direct `soleur:plan`:

- **FORBIDDEN:** Implementing product code (Write/Edit/Shell) before the plan artifact and tasks are written.
- **FORBIDDEN:** Ending after saving `plans/` + `tasks.md` without invoking `soleur:work` — the plan is a checkpoint, not a deliverable.
- **REQUIRED (Grok Build):** Invoke `soleur:work <plan-path>` (or `soleur:deepen-plan` when the plan requests it) via slash command — never substitute ad-hoc implementation.
- **Harness adapter:** `plugins/soleur/lib/harness.ts` — Grok uses `soleur:work`, `soleur:deepen-plan`; Claude uses Skill tool.

See `plugins/soleur/lib/workflow-fidelity.ts` (`HANDOFF_SKILLS`, `mandatorySuccessors('plan')`).
<!-- plan-anti-bypass-protocol:end -->

<!-- operator-typed-render:start -->
**Any message this skill PRINTS that tells the operator to run a skill or command renders at emit time.** The doc names it canonically (`soleur:<name>`, ADR-226); before printing, render it as the active harness's **operator-typed form** per `formatSkillInvocation` (`plugins/soleur/lib/harness.ts`), which owns the per-harness slash and sigil forms — the operator types that string into a fresh session where no routing contract is in context, so a bare canonical name is model-discretion there rather than a dispatch. This covers abort messages, `AskUserQuestion` prompts and options, `Display`/`echo` lines and resume prompts alike; an agent-read instruction stays canonical.
<!-- operator-typed-render:end -->

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
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` - use principles to guide planning decisions. Skip if already loaded (e.g., from a preceding `soleur:brainstorm`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/spec.md` if it exists - use as planning input
5. Announce: "Loaded constitution and spec for `feat-<name>`"

**Vocabulary.** Before committing a word that names a concept, check it against `knowledge-base/project/glossary.md` and use the sense its pointer settles; if the word is materially ambiguous and has no entry, hedge in the artifact and name the ambiguity. The instruction is stated once in [glossary-format.md](../kb-glossary/references/glossary-format.md) §The consumer pointer and is not restated here.

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

### 0.6. Pre-Research Premise Validation (Always)

Run BEFORE spawning any research (Phase 1) — research and downstream phases are expensive, and building a plan atop a stale premise wastes all of it. `brainstorm` Phase 1.1 does this validation when a brainstorm precedes plan, but `plan` is frequently entered directly (including the one-shot → plan path that skips brainstorm), so the cheap probe must also live here. This is distinct from Phase 1.7 reconciliation (which checks spec claims AFTER research returns) — this gate fires before research is even dispatched.

This also covers your **own** option-bounding capability claims — not just cited references. Before asserting that a repo tool/skill/script "only does X" or "can't do Y" to bound the plan's options, grep/read it first or phrase it as a question (`hr-verify-repo-capability-claim-before-assert`).

For every issue, blocker, dependency, or prior-art artifact the feature description **cites by reference**, verify it still holds:

1. **Cited GitHub issues / PRs** (`#N`, `Closes #N`, "blocked by #N", "follow-up to #N"): run `gh issue view <N> --json state,title,closedByPullRequestsReferences` and `gh pr view <N> --json state,merged` where applicable. If a blocker is already `closed`/`merged`, or the issue this plan targets is already closed by a merged PR, **the premise is stale** — surface via **AskUserQuestion** ("Issue #N appears already resolved by PR #M. Re-scope, or close as done?") rather than planning against it.
2. **Cited file/symbol/migration paths** (a function, route, component, or migration the plan assumes exists): confirm with `git show origin/main:<path>` or `git grep -n "<symbol>" origin/main`. If the cited artifact does not exist on `origin/main`, the premise ("fix the bug in X") may really be "X was never built" — flag it; the plan's shape changes from *fix* to *build*.
3. **"UI exists but is broken" claims**: distinguish *broken behavior* from *never-built*. If the description asserts a UI/endpoint misbehaves, confirm the route/component is actually present (`git grep`) before planning a behavioral fix — a silently-absent feature needs a build plan, not a patch.
4. **Proposed *mechanism* vs. the ADR corpus** (the feature names HOW to do it — a frontmatter flip, a new table, a polling cron, a config tier): grep `knowledge-base/engineering/architecture/decisions/` for the mechanism's keywords (not the cited issue number — issues don't know what an ADR decided) and read any hit's `## Decision` + `## Alternatives Considered`. A mechanism sitting in an ADR's rejected-alternatives table is not an unconsidered idea — it is an explicitly-rejected one; re-scope to "did the ADR leave a gap this still addresses?" rather than planning the rejected approach. Corollary: when the feature pins an *absolute* value (a fixed model/tier/limit), check its interaction with the *most capable* end of the range, not just the cheap end (an absolute `opus` reviewer pin is a downgrade on a Fable session). **Why:** #5087 — the issue's frontmatter-tiering approach matched the exact alternative ADR-053 rejected the day before (#5096); caught only at deepen-plan, three phases deep. See `knowledge-base/project/learnings/2026-06-11-brainstorm-grep-adr-corpus-for-proposed-mechanism-not-just-issue-refs.md`.

5. **The set that must do Y is whoever the Y-enforcing mechanism reaches — grep its call sites, not a nearby inventory; a shape rule over that set is a claim about every member — read each member's prescribed strings before writing it; and before designing a side channel out of a spawned CLI, run it once with `--output-format json` and read the result event.** **Why:** #8076 — the brainstorm's population (`TASK_INVENTORY`, five) was the heartbeat's liveness subset; the filing population was the nine `resolveOutputAwareOk` callers (the first missed cron fired two days after merge); a `[Scheduled]`-prefixed title rule would have broken campaign-calendar's `[Content] Overdue:` filings; a hook-written deny log plus nine caller edits dissolved once `permission_denials[]` was probed. See `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`.

Emit a one-paragraph **Premise Validation** note (what was checked, what held, what was stale) into the research-insights scratch so Phase 1.7 and the plan's "Research Reconciliation" section can carry it forward. If nothing is cited by reference, state "no external premises to validate" and proceed.

### 0.6b. Mechanism Minimality Gate (Always)

Runs after premise validation and before the Phase 1 fan-out, for the same reason Phase 0.7 sits there: a mechanism must be cut **before** anything expensive researches it. Premise validation (0.6) asks whether the plan's cited facts still hold; this asks whether the plan's proposed machinery is needed at all.

**1. Restate the ask as discrete properties — the Property List.** An issue routinely proposes a *mechanism* rather than a property — #7418 asked for an HTML-comment in-progress marker, while the properties underneath were "research survives a stall" and "a consumer can distinguish a half-written plan from a finished one". Write each property as one sentence naming an observable outcome. This restatement is what makes step 2 possible at all: two mechanisms cannot be compared until it is clear what they are both for.

**2. For every mechanism the FEATURE DESCRIPTION or issue proposes, name (a) the property it buys, and (b) whether a mechanism already on `origin/main` buys that property.** Scope this to the mechanisms named in the ask — the plan file does not exist yet and `## Files to Edit` is not written until Step 2, so do not guess at mechanisms the plan has not proposed (the discipline Phase 1.7.5 states for its own file list). Answer (b) by grepping, per `hr-verify-repo-capability-claim-before-assert`. A repo mechanism that already covers a property is the cheapest possible implementation of it. **Grep the AUTHORITY, and say which file you grepped:** a negative result against a *consumer* is indistinguishable from a real gap but carries the authority of a command with an exit code. If the ask itself asserts "the repo does not have X" — briefs written by the session that lived an incident routinely do — that assertion is a claim to verify here, not a premise to build on.

**3. Cut before researching.** Any mechanism that buys no property in the list, or buys one an existing mechanism already covers, is removed here — not researched, not designed, not reviewed. Record each cut in one line (mechanism → property → what already covers it) as the **Cut List**. Emit both lists into the research-insights scratch, exactly as Phase 0.6 emits its Premise Validation note; Phase 1.7 persists them into `## Research Insights`, which is where `plan-review` reads them. A mechanism the ask did not name but the plan later invents is caught by Step 2's re-read of this list, not here.

**Why:** #7418 / ADR-176 — the plan delivered a five-value cursor vocabulary, two decision tables, a resume cap with a strict-advance rule, a bounded-deletion rule, and a branch selector with a tiebreak. The second property was already free: `## Acceptance Criteria` appears in all three detail-level templates, is written last, and `soleur:one-shot` was already asserting on it. The plan never compared its new mechanism against the one already in the codebase; a twelve-agent review then found twelve blocking defects behind a 285/285 green suite, and **nine of them dissolved with the machinery** when the redesign landed. See `knowledge-base/project/learnings/2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md`.

### 0.6c. Value-Proposition Measurement (Conditional)

Fires when a plan's justification is a **cost or performance saving** ("saves an expensive fan-out", "avoids re-running X", "cuts N minutes"). Quantify the saving at plan time and **name the command that produced the number** — the same shape as Phase 1.8's budget check, which records a measured baseline rather than an asserted one.

Measure the thing actually claimed: if the case is "protects an expensive block", identify *which* block is expensive before designing the protection. If the saving cannot be measured at plan time, say so explicitly and record what would measure it — an unquantified saving is a hypothesis, and it must not be the sole justification for a mechanism that survives 0.6b.

**Why:** #7418 / ADR-176 — the plan's stated case was "save an expensive research fan-out", and which fan-out was expensive went unmeasured until *review*, where `soleur:engineering:review:performance-oracle` established that the checkpoint boundaries subdivide neither expensive block: all five agents under `plugins/soleur/agents/engineering/research/` are pinned cheap (`grep -l '^model: haiku' plugins/soleur/agents/engineering/research/*.md` returns 5), while the un-pinned eleven-agent Phase 2.5 domain fan-out — the real cost — was unprotected either way. The answer was one grep of agent frontmatter, three phases earlier.

### 0.7. Skeleton Checkpoint (Always)

Phase 1 dispatches the research fan-out — the most expensive stretch of this skill. Write the plan
file **before** it runs, then persist each phase's findings as they land, so a stall costs one phase
instead of the whole run (#7418, ADR-176).

Everything this phase needs is already in hand: Phase 0.6 ran `gh issue view <N> --json state,title`
for every cited issue, so the title — and therefore the slug — is free at this point.

**1. Resolve the destination from the repo root, not the ambient CWD.**

```bash
PLANS_DIR="$(git rev-parse --show-toplevel)/knowledge-base/project/plans"
BR=$(git branch --show-current)
```

A CWD-relative path can land the skeleton in the bare repo root, where the next sync clobbers it
(`2026-05-15-one-shot-plan-subagent-cwd-divergence.md`). Use `$PLANS_DIR` everywhere below —
including the selector — not a relative path.

**2. Convert title to filename:** add today's UTC date prefix, strip the prefix colon, kebab-case,
add a `-plan` suffix.

- Example: `feat: Add User Authentication` → `2026-01-21-feat-add-user-authentication-plan.md`
- Keep it descriptive (3-5 words after the prefix) so plans are findable by context.
- **Freeform arm:** Phase 0.6 only fires when refs are cited, so an invocation with no `#N` has no
  issue title. Derive the slug from the feature description instead.
- This is the **only** filename-derivation site in this skill. Step 2 refines the frontmatter
  `title:`; it does not re-derive the path. A `git mv` is reserved for a genuinely misleading slug,
  at finalization only.

**3. Select this branch's plan, if one already exists.** Match on the frontmatter `branch:` key —
a run that begins at 23:5x UTC and resumes after midnight derives a *different* filename at step 2,
so a fresh derivation would write a second file beside its own work.

```bash
# Frontmatter-bounded per candidate. A plan that DOCUMENTS this mechanism carries `branch:` in its
# body, so a whole-file `grep -l "^branch: …"` selects on documentation — the #4724 class in the
# sibling key. Bound the read to the leading `---` block, and tolerate a quoted value.
PLAN=""
for f in "$PLANS_DIR"/*.md; do                      # non-recursive: plans/archive/ excluded
  [[ -e "$f" ]] || continue                         # no-match glob leaves the literal pattern
  [[ "$(head -n 1 "$f")" == "---" ]] || continue    # no leading frontmatter -> not a plan
  v=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit}
           /^branch:/{ sub(/^branch:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit }' "$f")
  [[ "$v" == "$BR" ]] || continue
  PLAN="$f"                                         # tiebreak: highest date prefix, then newest
done                                                # mtime — the glob is already sorted by name
```

Duplicate `branch:` values exist on `main`, so the loop must keep scanning and apply the tiebreak
rather than stopping at the first hit.

**4. Branch on what the selected file contains.** `## Acceptance Criteria` is the completion
predicate: it is the one heading present in all three detail-level templates, and it lands last,
after every expensive phase. The skeleton writes `## Overview` and nothing else, so a stub can never
carry it. (`## Overview` is **not** part of the predicate — the MINIMAL template has none.)

| Existing state | Action |
|---|---|
| No file for this branch | Write the skeleton (step 5) |
| File exists, **no** `## Acceptance Criteria` | An interrupted run's checkpoint. **Never re-write the skeleton.** If it already carries `## Research Insights`, skip the Phase 1 fan-out and continue from Phase 1.7's exit; otherwise continue to Phase 1 |
| File exists **with** `## Acceptance Criteria` | A finished plan. **Never overwrite.** Headless: return the path and let the pipeline advance. Interactive: ask |
| Selector matched nothing | Use the filename derived at step 2 |

**5. Write the skeleton.** Frontmatter carries only what Phase 0.6 already knows:

```yaml
title: "<from gh issue view --json title>"
date: <UTC date>
slug: <the kebab title from step 2, without the date prefix or -plan suffix>
branch: <git branch --show-current>
issue: <N>                 # provisional — planning may re-target
```

Then `## Overview`, and nothing else.

**Deliberately absent: `lane:`, `type:`, `closes:`, `priority:`, `domain:`,
`brand_survival_threshold:` and `requires_cpo_signoff:`.** Every one is derived *after* research.
Pre-seeding `lane:` is actively harmful — it bakes in the fail-closed `cross-domain` value, which
*widens* the Phase 2.5 domain fan-out this checkpoint exists to protect. `issue:`/`closes:` are
decided by planning, not by the invocation, so the skeleton's `issue:` is provisional and
finalization rewrites both unconditionally.

**No progress key.** Completion is asserted from content (`## Acceptance Criteria`), never from a
dedicated frontmatter cursor. A second progress signal can disagree with the file's own content,
and every such disagreement resolves to a fail-open arm — see ADR-176 §Considered Options 6.

**Stub no conditional section.** The expected heading set depends on the detail level chosen at
Step 4 — after research — and the conditional sections are gate-triggered. A placeholder for a
section the finished plan legitimately skips trips `deepen-plan`'s halt gates. For the same reason,
placeholder prose must avoid the literal tokens `TODO`, `TBD`, `N/A` and `placeholder`.

**Fog belongs in the roadmap.** In-scope product work you cannot yet state as a precise question goes to `## Not Yet Specified` in `knowledge-base/product/roadmap.md` via the `soleur:product-roadmap` workshop, never into a plan `TBD`; plan does not edit roadmap.md. Implementation unknowns stay in the plan.

**Sanitize the Overview.** Write a restatement in this skill's own voice, never a verbatim paste of
the issue body. [lint-infra-no-human-steps.py](../../../../scripts/lint-infra-no-human-steps.py)
scans this directory and `.claude/hooks/iac-plan-write-guard.sh` gates the Write itself; both reject
prose pairing a human-actor token with an infrastructure imperative, and an issue body frequently
contains one.

**Write-denial arm.** The write guard is a PreToolUse *deny* hook. On denial, retry once with a
minimal Overview (title only). If still denied, **proceed skeleton-less** and note the reason in the
Session Summary — degrading to the pre-#7418 behaviour rather than aborting a run the operator is
paying for. Do not reach for the guard's acknowledgement opt-out to force the write: it asserts a
real infrastructure step was reviewed, which would be false here.

## Main Tasks

### 1. Local Research (Always Runs - Parallel)

<thinking>
First, I need to understand the project's conventions, existing patterns, and any documented learnings. This is fast and local - it informs whether external research is needed.
</thinking>

Run these agents **in parallel** to gather local context:

- Task soleur:engineering:research:repo-research-analyst(feature_description)
- Task soleur:engineering:research:learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, CLAUDE.md guidance, technology familiarity, pattern consistency
- **Learnings:** documented solutions in `knowledge-base/project/learnings/` that might apply (gotchas, patterns, lessons learned)

These findings inform the next step.

### 1.4. Network-Outage Hypothesis Check (Conditional)

If the feature description matches any of the patterns `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive substring match on the feature description), read [plan-network-outage-checklist.md](./references/plan-network-outage-checklist.md) and require its output in the `## Hypotheses` section of the final plan.

<!-- lint-infra-ignore start: describes a gate trigger / a past defect; prescribes no operator step (pre-existing on main, surfaced when #8301 staged this file) -->
Also fire this gate when the feature description names `terraform apply` (with or without `-target=`) against a resource whose definition contains `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block. The provisioner block makes SSH a hard apply-time dependency that the prose-only keyword scan won't detect. **Why:** #3061 — apply on `terraform_data.deploy_pipeline_fix` hit `ssh: handshake failed: connection reset by peer` despite zero SSH keywords in the plan, because the firewall allowlist had drifted out from under the operator's egress IP.
<!-- lint-infra-ignore end -->

The checklist enforces an L3->L7 diagnostic order: firewall allow-list and DNS/routing MUST be verified before sshd/fail2ban/service-layer hypotheses. Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`, this is a hard rule -- plans that propose sshd or fail2ban fixes without first verifying firewall + egress IP are workflow violations.

When a trigger pattern matches, emit rule-application telemetry so the weekly aggregator records this gate fired (see AGENTS.md `hr-ssh-diagnosis-verify-firewall`):

```bash
echo 'SOLEUR_RULE_APPLIED rule=hr-ssh-diagnosis-verify-firewall note=When a plan addresses an SSH/network-connectivity s'
```

This step is a single file read, not a subagent spawn. If the feature description does not match any trigger pattern, skip this step silently.

### 1.5. Community Discovery Check (Conditional)

**Read `plugins/soleur/skills/plan/references/plan-community-discovery.md` now** for the full community discovery procedure (stack detection, coverage gap check, soleur:engineering:discovery:agent-finder). Skip if no uncovered stacks detected.

### 1.5b. Functional Overlap Check

**Read `plugins/soleur/skills/plan/references/plan-functional-overlap.md` now** for the functional overlap check procedure (always runs, spawns soleur:engineering:discovery:functional-discovery agent).

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

- Task soleur:engineering:research:best-practices-researcher(feature_description)
- Task soleur:engineering:research:framework-docs-researcher(feature_description)

### 1.7. Consolidate Research

After all research steps complete, consolidate findings:

- Document relevant file paths from repo research (e.g., `app/services/example_service.rb:42`)
- **Include relevant institutional learnings** from `knowledge-base/project/learnings/` (key insights, gotchas to avoid)
- Note external documentation URLs and best practices (if external research was done)
- List related issues or PRs discovered
- Capture CLAUDE.md conventions
- **Reconcile spec claims against codebase reality.** If the soleur:engineering:research:repo-research-analyst returned any "Gap callouts" or equivalent mismatches, the plan MUST include a "Research Reconciliation — Spec vs. Codebase" section (3-column table: spec claim / reality / plan response) placed between "Overview" and "Implementation Phases". This prevents the plan from inheriting spec fiction (e.g., claimed infrastructure that doesn't exist) as phase estimates. See `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`.

**Persist the research to the plan file now — this is the write that makes the Phase 0.7 checkpoint
pay.** Write a `## Research Insights` section into the plan holding the consolidated findings above:
the relevant file paths, the applicable institutional learnings, any external documentation and best
practices, the related issues and PRs, the CLAUDE.md conventions, the **Premise Validation** note
carried forward from Phase 0.6, and the **Property List** plus **Cut List** carried forward from
Phase 0.6b. The property list is what `plan-review` reads to ask "which requirement does this
mechanism satisfy?", so it must reach the file — a consumer pointed at an artifact no producer writes
will silently skip the check.

Everything above this line was bought with the fan-out. A checkpoint that only reserved a filename
would still lose all of it to a stall here. `deepen-plan` later enriches this section; `plan` is what
first puts it on disk.

**Write it in a SINGLE Edit at the end of consolidation, never incrementally.** Phase 0.7 step 4
reads the section's presence as "the fan-out completed" and skips Phase 1 on that basis, so a
half-written section would be read as a whole one.

**Optional validation:** Briefly summarize findings and ask if anything looks off or missing before proceeding to planning.

### 1.7.5. Code-Review Overlap Check

After the plan draft has enumerated its `## Files to Edit` and `## Files to Create` sections (i.e., run this check AFTER Step 2 Issue Planning produces the file list, and BEFORE Step 4 Detail Level selection), verify whether any open code-review issues touch files the plan intends to modify. This prevents two failure modes:

- **Rework:** a pre-existing scope-out names a file the plan will rewrite — if unnoticed, the plan ships, then the scope-out surfaces and drives a second refactor PR that could have been folded in.
- **Double-counting:** the review phase files a new scope-out for a concern a still-open issue already tracks.

**Procedure:**

1. Read the plan's `## Files to Edit` and `## Files to Create` sections (the plan draft exists by this point). Extract every file path. If the plan is still being drafted and those sections are not yet written, defer this check until they exist rather than guessing from the feature description — guessing produces false negatives.

2. Query open code-review issues. **Use two-stage piping (`--json` then a standalone `jq --arg`), not single-stage `gh --jq` with `--arg`.** The `gh` CLI does NOT forward `--arg` to its embedded jq; a single-stage form produces `unknown arguments` at runtime. See learning `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

    ```bash
    ISSUES_JSON=$(mktemp -t open-review-issues.XXXXXXXX.json)
    gh issue list --label code-review --state open \
      --json number,title,body --limit 200 > "$ISSUES_JSON"
    echo "ISSUES_JSON=$ISSUES_JSON"
    ```

3. For each planned file path, search the issue bodies using standalone `jq` with `--arg` (safe against regex metacharacters in paths):

    ```bash
    jq -r --arg path "<file-path>" '
      .[] | select(.body // "" | contains($path))
      | "#\(.number): \(.title)"
    ' "$ISSUES_JSON"
    ```

    A later Bash call does not inherit `ISSUES_JSON`, so carry the echoed path forward (or
    re-derive it in the same call). Do not substitute a fixed name: a concurrent `soleur:plan`
    would overwrite the file between the write and this read.

4. If any matches are returned, write a `## Open Code-Review Overlap` section to the plan file with a one-line bullet per match and an explicit disposition for each:

    > X open scope-outs touch these files: #2466 (Range cache), #2483 (helper extraction). Fold in / acknowledge / defer: …

    For each match, the planner MUST explicitly choose one of:

    - **Fold in:** plan extends to close the scope-out in the same PR. Add the scope-out's file paths to `## Files to edit` and note `Closes #<N>` in the PR-body reminder.
    - **Acknowledge:** plan deliberately does NOT fix the scope-out (e.g., different concern, needs its own cycle). Record a 1-sentence rationale. The scope-out remains open.
    - **Defer:** plan is not the right place; update the scope-out issue with a re-evaluation note (e.g., "revisit after feat-X lands"). Do NOT silently leave the overlap unaddressed — the reviewer will re-surface it.

5. If no matches, still record `## Open Code-Review Overlap` with `None` so the next planner can see the check ran.

**Why this matters:** In the 2026-04-17 window, PR #2486 closed three scope-outs (#2467 + #2468 + #2469) because the planner noticed the overlap. PRs #2463 and #2477 grew the backlog instead because no overlap check ran. This phase makes the #2486 pattern the default, not the exception. See `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md`.

### 1.8. Skill Description Budget Check (Conditional)

**Phase 1 baseline.** If the feature description, research findings (1.1), or repo grep (Phase 1.7 consolidation) surfaces a candidate `description:` edit to any `plugins/soleur/skills/*/SKILL.md`, run the budget one-liner now (Node form, see [`knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`](../../../knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md) **Measurement one-liner** section). Record baseline headroom in Research Insights.

**Step 2 re-check.** Once `## Files to Edit` is finalized in Step 2 (Issue Planning), re-run the one-liner if any candidate `description:` edit landed in the file list — including candidates the planner introduced in Step 2 that Phase 1 did not surface. The check fires on the final list, not the Phase 1 candidate set.

**Headroom failure action.** If either check reports < 10 words remaining against the cumulative cap — `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts`, which is the enforcing gate and the only authority on the number —, include exact sibling-trim text (before/after) in `## Files to Edit` before proceeding. Skip silently if no SKILL.md `description:` edit is ever candidate or finalized.

### 2. Issue Planning & Structure

<thinking>
Think like a product manager - what would make this issue clear and actionable? Consider multiple perspectives
</thinking>

**Title & Categorization:**

- [ ] Draft clear, searchable issue title using conventional format (e.g., `feat: Add user authentication`, `fix: Cart total calculation`)
- [ ] Determine issue type: enhancement, bug, refactor
- [ ] Refine the frontmatter `title:` drafted at Phase 0.7 into its final searchable form. The **filename is already fixed** — Phase 0.7 derived it before the research fan-out and this step does not re-derive it. A `git mv` is reserved for a genuinely misleading slug, at finalization only.

**Stakeholder Analysis:**

- [ ] Identify who will be affected by this issue (end users, developers, operations)
- [ ] Consider implementation complexity and required expertise

**Content Planning:**

- [ ] Choose appropriate detail level based on issue complexity and audience
- [ ] List all necessary sections for the chosen template
- [ ] Gather supporting materials (error logs, screenshots, design mockups)
- [ ] Prepare code examples or reproduction steps if applicable, name the mock filenames in the lists
- [ ] When planning a directory rename, enumerate ALL files in the target directory as potential self-reference holders -- directory trees and conceptual prose derived from the directory name don't match path-pattern greps
- [ ] When the rename plan also sweeps every reference to the old path, exclude the feature's OWN planning artifacts (`plans/<this-plan>.md`, `specs/feat-<branch>/tasks.md`, `specs/feat-<branch>/session-state.md`) from BOTH the sweep file-list AND the residual-zero AC, exactly like `**/archive/**` -- they are point-in-time migration records that must cite the old path. A residual-zero AC and a "plan retains old path" AC are mutually contradictory unless the carve-out covers all three artifacts, not just the plan file. See learning `2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`.
- [ ] When the plan prescribes scoping a helper function by a new column/predicate, `rg` the codebase for every other inline query on the same table that BYPASSES the helper (id-based lookups, pre-helper historical queries, WS-handler inline SELECTs) and list each as a `Files to Edit` entry -- sibling queries are the most common silent backdoor after a tenant-scope change. See learning `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md`.
- [ ] When the plan prescribes any path glob (e.g., `apps/foo/**`, `**/doppler*.{yml,yaml,sh}`, `.github/workflows/*foo*.yml`), verify each glob matches ≥1 real file via `git ls-files | grep -E '<translated-glob>'` AND for negative-coverage gates (security gates, denylist filters, sensitive-path detectors) enumerate sibling files at the same architectural depth — globs constructed from a plan miss files the plan never inventoried. See AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g` and learning `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md`.
- [ ] **Wrapper-vs-curl check before adopting a workflow wrapper.** Before prescribing `claude-code-action`, `peter-evans/create-pull-request`, or any wrapper that constrains workflow architecture (token-revoking post-steps, hardcoded auto-merge, mandated job ordering), ask: "what does this look like as 5 lines of `curl` + `jq`?" If the answer is "fine," skip the wrapper. The wrapper's value is in agent tool-use loops or PR-creation generality; a single-shot LLM call or single-PR workflow doesn't need it. **Why:** 2026-05-11 #2720 v1 plan adopted `claude-code-action` and contorted into a two-job split + matrix to dodge its post-step token revocation; v2 dropped the wrapper and 4 P0 issues dissolved. See `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.
- [ ] **Paper-resolution lint.** Every FR/AC added to fold a review finding MUST cite the implementation location — e.g., `<script-file>:<line>`, `<workflow-file>:<section>`, or `prompt:step-N`. Without the pointer, the FR is paper — the planner could not encode the fix in code, only in prose, and the implementer will discover the gap at soleur:work time. **Why:** 2026-05-11 #2720 v1 plan folded 6 spec-flow P0s as FRs/ACs; spec-flow re-validation against the plan caught 4 as "RESOLVED in spec, NOT IMPLEMENTED in code." Same learning file.

### 2.5. Domain Review Gate

After generating the plan structure, assess which business domains this plan has implications for. This gate enforces constitution line 122: plans must receive cross-domain review before implementation.

**Step 1 — Domain Sweep:**

1. **Brainstorm carry-forward check:** If the brainstorm document (loaded in Phase 0.5) contains a `## Domain Assessments` section, carry forward the findings. Extract relevant domains and their summaries. Skip fresh assessment.

2. **Fresh assessment (if no brainstorm or no `## Domain Assessments` section):** Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Assess all 8 domains against the plan content in a single LLM pass using each domain's Assessment Question. Use semantic assessment — not keyword matching.

3. **Spawn domain leaders:** For each domain assessed as relevant **except Product** (handled in Step 2), spawn the domain leader as a blocking Task using the Task Prompt from brainstorm-domain-config.md, substituting `{desc}` with the plan summary. Spawn in parallel if multiple are relevant.

4. **Collect findings:** Wait for all domain leader Tasks to complete. Each returns a brief structured assessment. If a domain leader Task fails (timeout, error), write partial findings for that domain with `Status: error` and continue with remaining domains.

**Step 1.5 — Brainstorm Specialist Carry-Forward Gate:**

After domain sweep, scan the brainstorm document's `## Domain Assessments` section (and any `## Capability Gaps` section) for domain leaders that recommended specific specialists by name (e.g., "delegates to soleur:marketing:conversion-optimizer", "recommends soleur:marketing:copywriter for cancellation copy", "invoke soleur:product:design:ux-design-lead for wireframes"). Build a `REQUIRED_SPECIALISTS` list from these recommendations.

For each specialist in `REQUIRED_SPECIALISTS`:

1. If the specialist will be invoked by the Product/UX Gate pipeline below (soleur:product:design:ux-design-lead, soleur:marketing:copywriter, soleur:product:spec-flow-analyzer), mark it as "covered by UX Gate" — it will run in Step 2.
2. If the specialist is NOT covered by the UX Gate pipeline (e.g., soleur:marketing:conversion-optimizer, soleur:marketing:retention-strategist, soleur:marketing:pricing-strategist), invoke it as a Task now with a scoped prompt derived from the recommendation context. Spawn in parallel if multiple.
3. Record all brainstorm-recommended specialists in the Domain Review section under `**Brainstorm-recommended specialists:**`.

**Enforcement:** Specialists recommended by name in brainstorm domain assessments MUST be either invoked or explicitly declined by the user via AskUserQuestion ("Domain leader recommended [specialist] for [reason]. Run now / Skip with acknowledgment"). Silent skipping is a workflow violation. **Why:** In #1078, the CMO recommended soleur:marketing:conversion-optimizer and soleur:marketing:copywriter for the cancellation flow, but the plan skill silently wrote them into `Skipped specialists:` without asking, producing UX artifacts that lacked brand review.

**Step 2 — Product/UX Gate:**

**Mechanical UI-surface override (runs FIRST, before the subjective relevance check).** Scan the plan's `## Files to Create` AND `## Files to Edit` against the shared UI-surface term list + glob superset (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`). If any path matches, **force Product-relevant = true AND tier = BLOCKING**, regardless of what the Step-1 semantic sweep concluded. This closes the silent-skip hole where a UI feature whose sweep judged Product NONE would skip the gate entirely (a UI feature must never reach `## NONE` by subjective judgment alone). A plan that only *discusses* UI but *implements* orchestration/docs (no UI-surface file in its Files lists) is exempt and may be NONE.

After Steps 1 and 1.5 complete, if Product domain was flagged as relevant (by the sweep OR the mechanical override above), run the three-tier classification:

- **BLOCKING**: Creates new user-facing pages, multi-step user flows, or significant new UI components — including modals, dialogs, confirmation flows, and interstitials with emotional or persuasive copy (e.g., signup flows, dashboards, onboarding wizards, chat interfaces, retention modals, cancel confirmation screens, prompts, banners)
- **ADVISORY**: Modifies existing user-facing pages or components without adding new interactive surfaces (e.g., layout changes, form updates, adding fields to existing screens)
- **NONE**: No user-facing impact

A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE.

**Mechanical escalation (overrides subjective assessment):** Scan the plan's "Files to create" list. If any new file path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, the tier is **BLOCKING** regardless of subjective assessment. Creating a new component file = new user-facing surface = UX review required. **Why:** In #1049, a notification prompt component was classified as ADVISORY because the agent judged it "not significant enough." The user had to manually trigger the UX gate post-plan.

**On BLOCKING:**

1. Run soleur:product:spec-flow-analyzer via Task with UI-flow-aware prompt: "Analyze the user flows in this plan. Map each screen, identify entry/exit points, dead ends, missing error states, and flows that drop the user. Focus on user journey completeness, not technical implementation."
2. Run CPO via Task with scoped prompt: "Assess the product implications of this plan: {plan summary}. Cross-reference against brand-guide.md and constitution.md. Identify product strategy concerns, flow gaps, and positioning issues. Output a structured advisory — do not use AskUserQuestion."
3. **Brainstorm carry-forward check.** Before invoking soleur:product:design:ux-design-lead, check the UX signal source. If the only UX validation is brainstorm carry-forward (brainstorm assessed the *idea*, not the *page design*), reject it: "Brainstorm validated the idea, not the page design. Proceeding to wireframes." Then continue to step 4. This check applies to BLOCKING tier only — ADVISORY and NONE tiers may still carry forward brainstorm UX findings.
4. Invoke soleur:product:design:ux-design-lead via Task with scoped prompt: "Create wireframes for these user flows: {flow list}. Platform: desktop. Fidelity: wireframe." **On the one-shot/pipeline path (no brainstorm ran), plan Phase 2.5 is the SOLE PRODUCER of wireframes — it must GENERATE the `.pen`, not defer.** If the agent self-stops because Pencil is unavailable, do NOT record a skip: run `bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/pencil-setup/scripts/check_deps.sh --auto` (installs `@pencil.dev/cli`; auth via `PENCIL_CLI_KEY` from Doppler `soleur/dev`) and re-invoke. **Hard-block** (do not proceed, do not write to `Skipped specialists:`) only if auth is genuinely unsatisfiable or Node < 22.9.0, with a single instruction: "Provision PENCIL_CLI_KEY in Doppler soleur/dev (or `pencil login`), or install Node ≥ 22.9.0, then re-run plan." The two permitted outcomes are a committed `.pen` or this hard-block — `soleur:product:design:ux-design-lead` may never appear in `Skipped specialists:` for a UI feature (`wg-ui-feature-requires-pen-wireframe`). **Verifier asserts the invariant, not the proxy:** confirm the `.pen` exists on disk (non-empty) under `knowledge-base/product/design/{domain}/` and is referenced in the spec FRs — not "specialist reported done"; set `Pencil available: yes`.
4b. **Wireframe review pause.** soleur:product:design:ux-design-lead ends by running `xdg-open <screenshots-directory>`, so the wireframes are already open when it returns here. A Task subagent cannot collect operator input (`2026-05-12-task-subagent-prompt-text-only.md`), so the review pause lives in this orchestrator, right after the step-4 invocation. Mode-branch gate (`2026-03-27-skill-defense-in-depth-gate-pattern.md`): always run, branch on mode.
   - **Interactive arm** (interactive plan session): `AskUserQuestion` — "Wireframes are open for review at `<screenshots-dir>`. Approve and continue, or request changes?" Options: **Approve** → **record the approved design's aesthetic direction to the taste-profile** (the agent surface's write path — `soleur:product:design:ux-design-lead` never writes taste itself; #5990/ADR-090): `bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/taste-profile-update.sh knowledge-base/product/design/taste-profile.md <context> aesthetic-direction <approved-direction> "$(date -u +%F)"` (`<context>` = the design's surface enum, `<approved-direction>` = a sanitized lowercase-hyphen token); then continue to step 5 (Content Review Gate). **Request changes** → collect a free-text note, re-invoke `soleur:product:design:ux-design-lead` with `feedback: <note>` plus the existing `.pen` path, let it re-export + re-open, then re-ask. **Loop until Approve** — the Approve branch is the only exit (no dead end).
   - **Headless / pipeline arm:** mirror the auto-accept in the `On ADVISORY:` block below (step 1 — "If in pipeline/subagent context … auto-accept … proceed silently"). When plan runs in any non-interactive context — `HEADLESS_MODE=true`, no TTY, `soleur:one-shot`, `soleur:go --headless`, OR invoked with a plan-file-path argument (the one-shot path chains plan inside a Task subagent, `one-shot/SKILL.md:70`) — **do NOT pause.** Record `wireframes ready for async review at <dir>` and continue to step 5. **Load-bearing:** the subagent / file-path context is inherently non-interactive — the headless arm MUST fire there or the autonomous pipeline hangs on `AskUserQuestion`.
   - **Why:** wireframes are a visual artifact the operator must eyeball before the design freezes into the spec; the headless suppression honors `one-shot/SKILL.md:11` ("no per-phase approval gates"). Keep this mode predicate in sync with brainstorm Phase 3.55b and the canonical Phase 0.4 mode-detection block (`brainstorm/SKILL.md:101`) — the four context terms (`HEADLESS_MODE`, no-TTY, `soleur:one-shot`, `--headless`) must stay aligned across all copies; the plan-file-path term is a plan-specific addition.

5. **Content Review Gate.** Check if any domain leader (CMO, CRO, CPO, or other) recommended a soleur:marketing:copywriter or content specialist in their Step 1 assessment. If yes: invoke soleur:marketing:copywriter agent via Task with prompt: "Review the planned page content for brand voice compliance, value proposition clarity, and messaging effectiveness. Reference brand-guide.md." If soleur:marketing:copywriter ran successfully, add `soleur:marketing:copywriter` to `**Agents invoked:**`. If user declines, add `soleur:marketing:copywriter` to `**Skipped specialists:**` with the user's reason. If soleur:marketing:copywriter agent fails (timeout, error), add `soleur:marketing:copywriter` to `**Skipped specialists:**` with note `(agent error — review manually)` and set `**Decision:** reviewed (partial)`. If no domain leader recommended a soleur:marketing:copywriter, skip this step silently. This gate also fires on ADVISORY tier when a domain leader recommended a soleur:marketing:copywriter — the recommendation is the signal, not the tier.
6. Phase 3 SpecFlow is skipped (soleur:product:spec-flow-analyzer already ran in step 1 with UI-aware prompt — avoids duplicate invocation).
7. If any agent in the pipeline fails (timeout, error), write partial findings with `Decision: reviewed (partial)`. **BLOCKING gate enforcement:** If the tier is BLOCKING and a required specialist failed, do NOT silently proceed. For **`soleur:product:design:ux-design-lead`** specifically there is NO "skip" option — it is a non-skippable producer (step 4): retry via `pencil-setup --auto`, or hard-block until Pencil is provisioned. For **soleur:marketing:copywriter / soleur:product:spec-flow-analyzer** failures, use AskUserQuestion: "BLOCKING Product/UX Gate: [specialist] failed ([reason]). How to proceed?" Options: (a) **Retry now**, (b) **Skip with acknowledgment** (soleur:marketing:copywriter/spec-flow only — never soleur:product:design:ux-design-lead), (c) **Defer to next session**. Record the choice in the Domain Review section. For ADVISORY tier or non-specialist agents, proceed silently with partial findings as before.

**On ADVISORY:**

1. If in pipeline/subagent context (plan file path was provided as argument, not interactive): auto-accept, write Product/UX Gate subsection with `Tier: advisory, Decision: auto-accepted (pipeline)`, proceed silently.
2. If interactive: display notice via AskUserQuestion: "This plan modifies existing UI. Run UX review?" Options: "Yes, run full review" / "Skip — I'll handle UX manually". Record choice.
3. If user chooses full review, run the BLOCKING pipeline above.
4. **Content Review Gate (ADVISORY).** Regardless of the UX review choice, if any domain leader recommended a soleur:marketing:copywriter or content specialist, run step 5 from the BLOCKING pipeline (Content Review Gate). The recommendation is the signal, not the tier — modifying existing copy still benefits from content review.

**On NONE:** Skip — no Product/UX Gate subsection needed beyond the domain sweep finding.

If Product domain was NOT flagged as relevant in the sweep **AND the mechanical UI-surface override did not fire**, skip Step 2 entirely. If the override fired, Step 2 runs at BLOCKING tier regardless of the sweep.

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
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead, soleur:marketing:copywriter | [subset] | none
**Skipped specialists:** soleur:marketing:copywriter (<reason>) | none — `soleur:product:design:ux-design-lead` is NEVER valid here for a UI feature (non-skippable: `.pen` committed or hard-block per `wg-ui-feature-requires-pen-wireframe`)
**Pencil available:** yes | hard-blocked (auth/Node) | N/A (no UI surface)

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
2. Display: "CPO sign-off required at plan time before `soleur:work` begins. Invoke CPO domain leader if not already covered by Phase 2.5 carry-forward, or confirm CPO has reviewed the brainstorm."
3. Note in the plan that `soleur:engineering:review:user-impact-reviewer` will be invoked at review-time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

**Sign-off lifecycle staging — who participates at which phase:**

The set of mandatory leaders changes by lifecycle phase, and that is by design — different leaders weigh in at different decision points:

- **Brainstorm phase (framing time):** CPO + CLO + CTO are spawned in parallel when `USER_BRAND_CRITICAL=true`. Rationale: the approach has not been chosen yet, so all three lenses (product blast-radius framing, legal/compliance, architectural blast-radius) need to land before the plan exists. See `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## User-Brand-Critical Tag Processing`.
- **Plan phase (this gate):** CPO sign-off only. Rationale: the plan implements the approach already framed by all three brainstorm leaders; the plan-time sign-off is the single product-owner ack on the technical approach. CLO and CTO concerns from brainstorm should be reflected in the plan body (Risks section, Sharp Edges, Domain Review carry-forward) — they do not re-sign here.
- **Review phase (PR time):** CPO is not re-invoked; instead the `soleur:engineering:review:user-impact-reviewer` agent enumerates failure modes against the diff. Rationale: review-time concerns are diff-shaped, not approach-shaped.
- **Ship phase (preflight Check 6):** No human sign-off; mechanical gate that the section exists and the threshold is valid.

This tiered model is intentional — re-asking CPO/CLO/CTO at every phase would dilute the framing into ceremony. The framing question is asked once (brainstorm), the answer is locked in (plan), the diff is checked against the answer (review), the gate verifies the answer was given (ship).

If the threshold resolves to `aggregate pattern`, no per-PR sign-off is added but the section must still be present.

If the threshold resolves to `none` AND the diff touches a sensitive path (canonical regex defined in `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1), the section MUST contain a `threshold: none, reason: <one-sentence non-empty reason>` scope-out bullet. Without it, preflight will FAIL at ship time.

**Step 4 — Sharp-edge note.** When emitting the final plan output, add a Sharp Edges entry:

> A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.

**Why:** Triggered by #2887 — the dev/prd Doppler-config collapse shipped for months because every existing gate weighed the decision on technical and convenience axes only. The framing-time enforcement here, combined with deepen-plan Phase 4.6 (halt on missing section), preflight Check 6 (ship-time gate), and the `soleur:engineering:review:user-impact-reviewer` conditional agent, closes the workflow-level loop.

### 2.7. GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

If the plan touches regulated-data surfaces (per the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex — schemas, migrations, auth flows, API routes, `.sql` files), invoke `soleur:gdpr-gate` against the plan doc + the FR/TR sections being authored. Output is advisory-only with mandatory disclaimer; Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 trigger) prompt operator-acknowledged write to `compliance-posture.md` Active Items + GitHub issue with label `compliance/critical`.

**Also invoke when canonical regex misses but ANY of these hold:** (a) new processing activity using LLM/external API on operator-session-derived data, (b) brand-survival threshold `single-user incident` declared in the plan, (c) new cron/workflow that READS from `knowledge-base/project/learnings/` or `knowledge-base/project/specs/`, (d) new artifact distribution surface (plugin update, public PR body, package release). The canonical regex covers schema/auth/API code surfaces; these four expand coverage to cross-controller data-movement surfaces. **Why:** 2026-05-11 #2720 — plan touched none of the regex surfaces but added Anthropic-bound LLM-summarization of operator-session learnings + draft PRs to public repo; gate-time invocation surfaced a pre-existing Anthropic-DPA gap that no other gate caught. See `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.

Skip silently if no regulated-data surface is touched AND none of the (a)-(d) triggers fire.

### 2.8. Infrastructure-as-Code Routing Gate

[skill-enforced: soleur:engineering:infra:terraform-architect at plan Phase 2.8]

If the plan introduces infrastructure that needs to live somewhere — a server, a systemd service, a cron job, a vendor account, a DNS record, a TLS cert, a secret, a firewall rule, a monitoring webhook — route the implementation through Terraform (or another IaC mechanism already in the repo) at plan time. Do NOT bake "operator runs `ssh root@host && ...`", "operator runs `doppler secrets set X=...`", or "operator clicks through the vendor dashboard" into the plan's Implementation Phases. Per `hr-all-infrastructure-provisioning-servers`, manual provisioning is not an acceptable phase output.

**Detection** (case-insensitive substring scan of the plan draft + the feature description):

- `ssh root@`, `ssh deploy@`, `ssh ubuntu@`, `ssh <user>@<host>`
- `manually install`, `operator runs`, `operator installs`, `operator-driven`, `out-of-band`
- `systemctl enable`, `systemctl start`, `systemd unit`, `/etc/systemd/system/`
- `doppler secrets set` (vs reading via `doppler secrets get` which is read-only)
- `terraform import` of a resource that should have been created by Terraform
- vendor-dashboard wording: "go to the [Cloudflare|Hetzner|Stripe|Doppler|Better Stack|Sentry|R2|Supabase] dashboard and …", "in the … console click …"
- `cron`/`crontab -e`, `at <time>`, `journalctl` (when used for state, not diagnosis)
- new vendor account signups not already routed through `soleur:operations:service-automator` or `soleur:operations:ops-provisioner`

**If detected, invoke `soleur:engineering:infra:terraform-architect` with the plan draft and the detected phrases.** The agent's job is to reshape the affected Implementation Phases so the new resource lives in `apps/<app>/infra/*.tf` (extending the existing root, or creating a new one with the R2 backend per `hr-every-new-terraform-root-must-include-an`), with cloud-init/`runcmd` for first-boot config and an idempotent bootstrap script (e.g. `apps/<app>/infra/<resource>-bootstrap.sh`) for applying the change to already-running hosts without re-provisioning.

**Required output: `## Infrastructure (IaC)` section in the plan.** Mirror the `## Domain Review` heading contract. Required subsections:

- `### Terraform changes` — listed files (existing TF root + new resources), required providers + version pins, sensitive variable list (`TF_VAR_<name>` plus where the value comes from — Doppler service token, etc.).
- `### Apply path` — one of: (a) cloud-init-only (acceptable when the resource has not yet been provisioned), (b) cloud-init + idempotent bootstrap script (the default for existing infra), (c) taint + `terraform apply -replace` (only when the resource cannot be patched in place). State the chosen path and the expected downtime/blast-radius.
- `### Distinctness / drift safeguards` — `dev != prd` preconditions, `lifecycle.ignore_changes` callouts, state-storage notes (encrypted backend, secret values land in `terraform.tfstate`).
- `### Vendor-tier reality check` — when the chosen provider has free-tier limits that affect resource creation (e.g., Better Stack free tier rejects `betteruptime_policy`), document the tier gate (`count = var.<provider>_paid_tier ? 1 : 0`) before `apply` time.

**Why:** PR-F (#3940) plan baked in "operator installs inngest-cli + systemd unit via SSH" and "operator sets Doppler keys via CLI" as Phase X items. Both violate `hr-all-infrastructure-provisioning-servers`. The rule existed; no plan-time gate consulted it. The cost was a post-merge realisation that the entire operator checklist had to be redone as Terraform. See `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`.

Skip silently if the plan introduces no new infrastructure (pure code change against an already-provisioned surface). A plan that only edits files under `apps/<app>/src/` or `apps/<app>/server/` typically skips. A plan that introduces a new service, a new secret, a new vendor, or a new persistent runtime process does not.

### 2.9. Observability Quality Gate

[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]

Every plan whose Files-to-Edit includes a code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or that introduces any new infrastructure surface (per Phase 2.8 trigger set), MUST emit a `## Observability` section using the 5-field schema. A feature that requires SSH to verify observability is a feature without observability.

**Required schema (verbatim from `plan-issue-templates.md`):**

```yaml
liveness_signal:    # what / cadence / alert_target / configured_in
error_reporting:    # destination / fail_loud
failure_modes:      # list of {mode, detection, alert_route}
logs:               # where / retention
discoverability_test:
  command:              # one command an operator can run LOCALLY (NO ssh). preflight Check 10
                        # EXECUTES this in a sandbox under a 15s cap, so the first token must be
                        # an allowlisted probe verb (NO path-shaped exemption — wrap anything
                        # else in a committed repo-relative script invoked as `bash path/x.sh`),
                        # and the whole command must finish inside the cap. Rejects below.
  expected_output:      # the LITERAL string(s) the command prints — "200", "ok",
                        # "RELEASED or HOLD or ABORT". Check 10 substring-matches these against
                        # stdout, so a sentence DESCRIBING the output can never match.
  credentials_required: # OPTIONAL — only when the property has no unauthenticated substitute
```

**Reject conditions** (enforced at deepen-plan Phase 4.7 — see `deepen-plan/SKILL.md`):

- Section missing entirely.
- Any required field contains the substring `TODO`, `TBD`, `placeholder`, or `manual operator check` AS THE FIELD VALUE (a fallback note in surrounding prose mentioning TBD is allowed; the canonical "field is empty" reject regex is `^\s*<field>:\s*(TODO|TBD|placeholder|manual operator check)\s*$`).
- `discoverability_test.command` contains `ssh ` (with trailing space — distinguish "ssh " the verb from "ssh-free" in docs). A `credentials_required` declaration does **not** override this. <!-- markdownlint-disable-line MD038 -->
- `discoverability_test.command`'s first token is not on preflight Check 10's `PROBE_VERB_ALLOWLIST` (`curl bash grep rg jq python3 node bun printf git`). There is no path-shaped exemption — a first token containing `/` is subject to the same list. Check 10 executes this command inside a sandbox; the allowlist is schema validation ("can this run at all?"), not a security control, and every entry is an authority grant the sandbox — not the list — bounds. Wrap anything else in a repo-relative script committed in the SAME PR: it runs with `PATH=/usr/local/bin:/usr/bin:/bin`, `HOME` on tmpfs, no credential stores, and the repo read-only.
- `discoverability_test.credentials_required` is present but placeholder text. The field is **optional**; when a probe verifies a property with no unauthenticated substitute, state the credential scope and the justification (`"<scope> — <why no unauthenticated probe verifies the same property>"`) and Check 10 skips it explicitly (`SKIP-DECLARED`) instead of executing it. A declaration that says nothing waives nothing.
- `discoverability_test.command` is a whole test suite, a full build, or anything else that cannot finish inside preflight Check 10's **15-second cap**. Check 10 runs the declared command in a bubblewrap sandbox under `timeout 15s`; a longer command is killed at `rc=124` and reported as a FAILED probe (row 9), which is indistinguishable from the endpoint being down. A suite is the right command to TEST the thing and the wrong one to DISCOVER its signal — declare the smallest command that prints the signal `liveness_signal.what` already names. Wrapping in a committed repo-relative script satisfies the VERB allowlist, not this condition — a suite wrapped in a script is still a suite; the wrapper is the remedy for a multi-statement probe that is already fast. **Why:** #8010/PR #8412 — a plan declared its own 236-assertion gate suite here; Check 10 killed it with arms still passing.
- `discoverability_test.expected_output` is PROSE rather than a matchable literal. Check 10 tokenizes this field and asks whether any token is a substring of the command's stdout (preflight `## Step 10.6` *Expected-output matching semantics*; note the row-11 cell states the direction backwards and is a known defect in that table), so a sentence like `"the suite's final ledger line reports 0 failures"` cannot be relied on to match and the probe FAILS on a healthy system. (Not *never*: the tokenizer splits on `,`, `or`, quotes, brackets and `/`, so a prose value containing those yields fragments, and a long enough fragment that happens to occur in stdout matches by accident — which is worse than a clean FAIL.) State the literal(s) the command actually prints — `"200"`, `"RELEASED or HOLD or ABORT"`, `"ok"` — not a description of what they mean. **Absent** counts as violating this too: an empty `expected_output` parses to `""`, matches nothing, and surfaces at ship time as a row-11 "expectation drift" FAIL — the misdiagnosis this condition exists to prevent.

**Scope of the two conditions above (added #8412).** A non-placeholder `credentials_required`
short-circuits both: preflight row 4 (`SKIP-DECLARED`) precedes rows 9 and 11, so the command is
never executed and neither condition is reachable at ship time — `deepen-plan` Step 5 encodes this
and this list must not disagree with it. Otherwise they bind a `discoverability_test` this change
AUTHORS or AMENDS. They are not retroactive: measured at introduction, of the 856 plans under
`knowledge-base/project/plans/` carrying the block, ~372 declare a prose or block-scalar
`expected_output` and ~261 a suite-shaped `command`, every one of them compliant when written.
`soleur:deepen-plan` run against a pre-existing block REPORTS these two as findings and proceeds;
it HALTs on them only when the block is new or edited in the same change. Every other reject
condition in this list is unscoped and halts either way.

**Skip silently** when:

- Plan is pure-docs (no Files-to-Edit under code/infra paths above).
- Plan deletes-only (no new code/infra surface; revert PRs).

**Why:** #4116 — `inngest-heartbeat.service` was silently broken for 16+ hours. The plan that introduced it (PR-F #3940) passed every other plan-time gate but had no observability declaration; the operator-blind-zone aggregated across the substrate cascade (#4017 → #4111) until issue #4116 surfaced the gap. Codifying the gate at plan-time prevents the next feature from shipping a dark observability surface.

#### 2.9.1. Soak Follow-Through Enrollment (conditional)

If any Acceptance Criterion or the `liveness_signal` declares a **post-deploy soak / time-gated close criterion** — a signal that must hold for N days/hours before an issue closes or an ADR/amendment status flips (`adopting → accepted`), e.g. *"`op:founder-ambiguous` stays at ~0 for 7 days post-deploy"* — the plan MUST add a **Follow-Through Enrollment** deliverable so the closure is automated, not left to human memory (the recurring rot the daily follow-through sweeper exists to prevent — see [followthrough-convention.md](../../../../knowledge-base/engineering/operations/runbooks/followthrough-convention.md), §Soak trigger shape).

The deliverable names:

- the verification **script path** under scripts/followthroughs/ (named `<short-name>-<issue>.sh`) — exit 0 when the soak holds; for Sentry-rate soaks, mirror [reconcile-ff-only-sentry-4977.sh](../../../../scripts/followthroughs/reconcile-ff-only-sentry-4977.sh) with `start=` pinned strictly after deploy;
- the tracker's `<!-- soleur:followthrough script=… earliest=<deploy+Nd> secrets=… -->` directive + the `follow-through` label;
- any new `secrets=` to wire into `.github/workflows/scheduled-followthrough-sweeper.yml`.

This is enforced at ship time (fail-closed) by `soleur:ship` Phase 5.5's **Soak-Gated Follow-Through Enrollment Gate** + the `ship-soak-followthrough-gate.sh` PreToolUse hook; declaring it here means the work phase builds the probe instead of soleur:ship blocking PR-ready on a missing one. **Why:** 2026-06-29 — PR #5671 (#5673) and PR #5675 (#5689) both shipped soak-gated closures in prose with no enrollment; both trackers were left to rot until caught manually.

#### 2.9.2. Affected-surface observability (blind execution surfaces)

If the plan's Files-to-Edit touch a surface the operator/agent CANNOT directly inspect — an **agent bwrap sandbox** (`server/agent-runner-sandbox-config.ts`, `server/sandbox*.ts`, `server/bash-sandbox.ts`), a **container dispatch/readiness gate** (`server/cc-dispatcher.ts`, `server/agent-runner.ts`, `*agent-on-spawn*`, any `*readiness*`/`*self-stop*` path), or a **cron worker** — the `## Observability` block's `failure_modes` MUST additionally satisfy:

- Each `detection` names an **in-surface** probe (a signal emitted FROM the sandbox/container/worker), not only a host-side layer. A host gate cannot observe a sandbox's internal state.
- The probe's **structured fields discriminate ALL competing root-cause hypotheses in one event** (e.g. `source` / `gitKind` / `gitRevParseValid` for a host-vs-sandbox-mount split) — not a single boolean that emits for only one failure shape.

This is the affected-surface extension of `hr-observability-as-plan-quality-gate` — the diagnosis-first discipline for blind surfaces, enforced at review by `soleur:engineering:review:observability-coverage-reviewer` §Step 4.6. **Why:** #5733 — 6 blind server-side fixes over ~2 weeks because the failing agent-sandbox surface emitted no discriminating telemetry; one in-sandbox event decided the root cause the moment it shipped. See `knowledge-base/project/learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`.

### 2.10. Architecture Decision (ADR / C4) Gate

> **Rule `wg-architecture-decision-is-a-plan-deliverable` — migrated out of `AGENTS.rules.md` on 2026-09-10 (PR #8034).**
> Domain-scoped per `cq-agents-md-tier-gate`: the violation it prevents can only
> occur in this phase, which already enforces it, so it no longer costs every
> session's always-loaded budget. This is now its canonical home.
>
> When a plan makes or changes an architectural decision (ownership/tenancy boundary move, new substrate/trust boundary, or a reversal/extension of an existing ADR), the ADR write and C4 diagram update are deliverables of THAT plan — never a deferred follow-up issue [id: wg-architecture-decision-is-a-plan-deliverable] [skill-enforced: plan Phase 2.10]. **Why:** #5437 — always-enforce-workspace ADR/C4 was wrongly filed as deferred #5440; recorded architecture must not lag the change that creates it.

[skill-enforced: plan Phase 2.10 — `wg-architecture-decision-is-a-plan-deliverable`]

If the plan makes or changes an **architectural decision**, the ADR write and the C4 diagram update are **deliverables of THIS plan** — never a deferred follow-up issue. Phase 0.6 / line 112 already make you *read* the ADR corpus; this gate makes you *produce* the decision record when the plan creates one. Deferring an ADR/C4 update to "later" ships a system whose recorded architecture lies about its real one until someone reopens the issue (usually never).

**Detection** (the plan introduces or changes any of):

- A data-model **ownership / tenancy boundary** move (user-keyed → workspace-keyed, per-row → per-tenant, a new "X owns Y" relationship).
- A new **substrate or integration pattern** (a new queue, cron substrate, auth/credential boundary, external-service edge).
- A **resolver / dispatch / trust boundary** change (who resolves what, fail-closed semantics, a new cross-cutting invariant every consumer must honor).
- A **reversal or extension of an existing ADR** (you read it in Phase 0.6 and the plan diverges from or supersedes its Decision).
- Any change a future engineer would be surprised to find **undocumented** in `knowledge-base/engineering/architecture/`.

**If detected, the plan MUST emit an `## Architecture Decision (ADR/C4)` section** naming, as in-scope plan tasks:

- `### ADR` — the ADR to **create or amend** via `soleur:architecture` (number + one-line decision). New decision → new ADR; divergence from an existing one → amend that ADR's `## Decision` + add to its `## Alternatives Considered`. This is a task in the implementation phases, not a "see also." The chosen ordinal for a NEW ADR is **provisional** — a sibling PR can claim it during the pipeline (a collision surfaces as a red `adr-ordinals` on the PR after a Phase 7 sync — it is a required check — and `soleur:ship` catches it earlier at Phase 5.5). `soleur:ship`'s "ADR-Ordinal Collision Gate" re-verifies the next-free ordinal against `origin/main` before merge and after every Phase 7 sync; do not treat the plan-time number as final. **When you DO renumber, sweep the whole feature's artifact set for the old ordinal in the same edit** — `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-<slug>/` — because the renumber otherwise reaches only the ADR body/seed/code while the **plan + tasks + any AC that names the ordinal** keep the stale number (a `` `ADR-<old>-*.md` exists `` AC then verifies a nonexistent file). **Why:** #5945 chose ADR-081 → renumber to ADR-082 (#5952); #5990 collided TWICE in one ~2h pipeline (087→089 at rebase, 089→090 at ship as siblings claimed each free ordinal) and the first renumber left AC12 asserting a nonexistent `ADR-087-*.md` until review caught it (`2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`).
- `### C4 views` — which C4 view(s) (Context / Container / Component) change and how (e.g., "Container: repo connection edge moves from User to Workspace"). **The workflow edits the `.c4` model files DIRECTLY** (via the `architecture` skill / Edit tool, committed in THIS feature's lifecycle — not a separate issue). The `c4-edit` flag (commit `3c8849655`) gates ONLY direct end-user edits in the in-browser webapp editor (`PUT /api/kb/c4`, default OFF); it does **not** gate a workflow and the workflow never routes through that path. Concierge **and** the Claude Code plugin terminal are equally-trusted agent contexts that edit `.c4` on the filesystem and commit — do NOT instruct the implementer to "route the C4 edit through the Concierge."

  **C4 completeness mandate (load-bearing — no narrow-grep escape hatch).** Before writing the `### C4 views` task (INCLUDING a "no C4 impact" conclusion), you MUST actually READ all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — not a single keyword `grep`. A `grep` for the feature's own noun (e.g. `grep email-triage`) returning zero is **NOT** evidence of "no C4 impact": the relevant elements are frequently the feature's *external actors and systems* (a human role like an inbound email sender; an integration like Resend/Stripe/Twilio; a new data store), which are named by the vendor/role, not the feature. Enumerate, for the feature, EVERY: (a) **external human actor** (who sends/receives data — correspondents, reviewers, end recipients), (b) **external system / vendor** (inbound webhook, outbound API, third-party store), (c) **container/data-store** touched, (d) **actor↔surface access relationship** that changes (e.g. single-owner → workspace-Owner-shared). For each, confirm it is already modeled; if NOT, the `.c4` edit that adds it (element + `#external` tag if outside the boundary + the relationship edges + the `view … include` line in `views.c4` so it RENDERS) is an in-scope plan task. Reviewing all three `.c4` files for *correctness* also means fixing any element description the change falsifies (e.g. a "Solo founder" actor description when the change adds multi-Owner sharing). After editing, run the C4 validation tests (`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`) — a `view include` that references an undefined element fails there, not at `tsc`. A "no C4 impact" line in the plan MUST cite which actors/systems/relationships were checked and found already-modeled; an unsupported "None" is a reject condition. **The actor/system/relationship rubric does NOT reach the derived CARDINALITIES `model.c4` embeds in edge prose ("…across 10 workflows", "56 monitors"), which `c4-count-parity` gates as required context — so a "no C4 impact" conclusion MUST also be backed by a green `plugins/soleur/test/c4-count-parity.test.sh` run (that is its path — an earlier revision cited `apps/web-platform/test/`, where no such file exists, and #8050's planner concluded the gate was missing), not by reasoning about actors. **Why:** #7826/#7834 — adding the 56th cron monitor and the 12th heartbeat slug moved four counts on the `github -> sentry` edge and reddened the gate in a file the diff never opened.
- `### Sequencing` — if the decision is only *true* after a later slice (e.g. a soak-gated migration), the ADR is authored now describing the target state with a "status: adopting" note; it is **not** postponed to its own issue.

**Reject condition** (enforced at deepen-plan): an architectural decision is detected but the plan defers the ADR/C4 update to a follow-up issue, OR the `## Architecture Decision (ADR/C4)` section is missing while detection fires, OR the `### C4 views` task concludes "no C4 impact" without citing the external-actor / external-system / access-relationship enumeration it checked against all three `.c4` files (the C4 completeness mandate above).

**Skip silently** when the plan makes no architectural decision — a bug fix on an existing surface, a copy/UI tweak, a dependency bump, a pure-docs change. The test: would a competent engineer reading only the existing ADRs + C4 be *misled* about the system after this plan ships? If no, skip.

**Why:** 2026-06-16 ADR-044 workspace-connection brainstorm (#5437) — the always-enforce-workspace decision and its C4 connection-owner edge were initially filed as a *deferred* follow-up issue (#5440) instead of being part of the plan. The operator corrected it: the ADR/C4 update is intrinsic to the architectural change and must ship with it. No prior plan-time gate required producing (vs reading) an ADR. See `knowledge-base/project/learnings/2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue.md`.

### 2.11. Encryption Posture Gate

[skill-enforced: plan Phase 2.11 + deepen-plan Phase 4.10]

Every plan that introduces a persistent data store (a Hetzner volume, an R2 bucket, a Supabase table, a queue, a cache, a backup target, a log sink) or a new cross-component/network connection MUST emit a `## Encryption Posture` section using the field set below. "The provider handles it" and "the provider supports TLS" are not postures — they are the absence of one.

**Detection** (the plan's Files-to-Create/Edit match, OR the prose names a store class / a new cross-component connection):

- `\.tf$`
- `supabase/migrations/.*\.sql$`
- `cloud-init.*\.ya?ml$`
- `docker-compose.*\.ya?ml$`

**Required schema (verbatim from `plan-issue-templates.md`):**

```yaml
at_rest:          # per store: mechanism / evidence / defends_against / does_not_defend / disclosed_as / live_verification
in_transit:       # per connection: tls / cert_verification (on|off) / does_not_defend / disclosed_as
exception:        # present ONLY when mechanism is plaintext-exception OR cert_verification is off — justification / tracking_issue / reevaluate_when / expires_on
```

**Reject conditions** (enforced at deepen-plan Phase 4.10 — see `deepen-plan/SKILL.md`): section missing entirely while detection fires; a required field empty or matching the placeholder ban-list; `mechanism` or `at_rest` prose reading "the provider handles it" / "encrypted by default" with no named attestation / "supports TLS"; `does_not_defend` empty or "none"/"n/a"; a `plaintext-exception` or `cert_verification: off` row with no `exception` block, or one missing `tracking_issue` / `expires_on`.

**Skip silently** when the plan introduces no persistent store and no new cross-component connection — pure UI/docs/dependency-bump plans, or a change confined to an already-provisioned surface.

**Why:** ADR-140 and `knowledge-base/project/plans/2026-07-23-feat-encryption-posture-design-time-default-plan.md` (Plan Review Revisions R1-R11) — a new store or connection shipped with no declared encryption posture is undetectable at review time by name-similarity alone (a plaintext `hcloud_volume.workspaces` reads identically to its LUKS-backed sibling `hcloud_volume.workspaces_luks` until the device-binding chain is actually walked). Codifying the posture as a plan deliverable, resolved against real code by `lint-encryption-posture.py` (repo-root `scripts/`), closes the gap at design time instead of at incident time.

### 2.12. Guard Contract Gate

[skill-enforced: plan Phase 2.12 + deepen-plan Phase 4.11 + [lint-guard-contract.py](../../../../scripts/lint-guard-contract.py)]

If the plan's deliverable **includes a guard** — a guard, gate, lint, drift-check, assertion-based CI check, or anti-vacuity control — the plan MUST emit a `## Guard Contract` section carrying one `### Guard <n> — <name>` entry per guard, each with three fields.

**The class this exists to catch:** *a guard's WINDOW, CHOKEPOINT, or IDENTIFIER SET is narrower than the property it names.*

1. **Property** — the invariant in ONE sentence. Not "the sandbox is correct" but "no mount outside the declared set reaches the sandbox."
2. **Assembly** — every code path, array, file, and call site the property quantifies over. **Members drift; assembly is structural.** An "assembly" enumerated as the list of current members is not an assembly — it is a snapshot, and the next one-line edit invalidates it while the suite stays green. Name the *chokepoint* the members must flow through, and if there is more than one, say so: a guard scoped to one of three injection sites is the defect, not a partial fix.
3. **Mutation matrix** — **>= 3** edits that MUST drive the guard RED, derivable from the DESIGN rather than from the implementation as it happens to be shaped. At least one row MUST target the guard's **own dispatch** (a guard that reports "0 checked" and exits 0 is vacuous), and at least one MUST add a **second** member after a compliant first (a check that stops at the first member is itself an instance of the class). **A property about ORDER or LIFETIME needs a REORDER row, not a delete row** — deleting the write reds any suite that reads the artifact at all, while MOVING it reds only a suite that reads the artifact *during* the window the property is about; when every case reads state after the function returns, that is the one instant the property can never be violated at, so a delete-only battery certifies a property it never tested. Pair it with a case that observes INSIDE the window. **Why:** #7587 — moving `state_add` from before the poll loop to just before the rollback left 190/190 assertions green on a gate whose whole purpose is the cancellation window; see `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` §2.

4. **Harness rows** — at least one edit to the SUITE (not the guard) that MUST drive it RED, plus at least one must-PASS input that is NOT the canonical, differing in a way the contract explicitly permits. A matrix that mutates only the system under test cannot see a vacuous harness, and RED rows cannot detect a guard that rejects everything — only must-PASS rows can. **Why:** #7493 — four guards were each satisfiable by a stub: `diff "$1" canonical` scored 14/14 AND passed CI with the defect restored (every RED fixture was a `jq` edit OF the canonical, and the only must-PASS fixture WAS the canonical); a `mutate()` helper running inside `$( )` left 16 of 18 rows green while fully broken; a suite whose success was `fail == 0` exited 0 on `0 passed, 0 failed`; and a `pass()` count was blind to ~35 predicates embedded in Python. See `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`.

5. **Anchor** — when the guard compares a STORED value (a hash, manifest row, count floor) to the thing it protects, name what OUTSIDE the commit must also move for a weakening to pass: a merge-base diff, an independently reviewed registry, or a WORM ack. If one diff can edit both the value and the thing, the guard proves consistency, not integrity; and a `>= N` floor survives any substitution that keeps N, so pair it with set identity. **Why:** #8175 — see `knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`.

**Write the matrix BEFORE the guard.** A matrix derived from finished code tests the code that exists; a matrix derived from the design tests the property. This ordering is the whole point of the gate.

**One row must satisfy the guard's precondition and still fail the property — and every mechanism must be validated against the tree its own REMEDIATION produces, not the tree it finds.** Enumeration rows (is the marker present, is the population derived, does the floor fire) are statements about the population's *shape*; a property of the form "X implies Y" needs a row where X holds and Y fails. Without one, the matrix is measuring its own bookkeeping. The second half is the scheduling problem: a mechanism measured against the current tree can be sound now and dead after the backfill, and nothing in the authoring loop prompts the re-check because the post-change state does not exist yet — so for each mechanism, name the mutation that defeats it *after* the change lands. When the remediation writes text, the first candidate is always **"does the remediation's own text match the classifier?"** Two corollaries: an aggregate floor cannot express a per-member property (if the property is per-member, the artifact is an inventory, not a count); and after renaming any heading a gate keys on, re-run that gate and assert the **entry count** moved, not merely that it exits 0. **Why:** #8299 — a 454-line plan whose 13 rows all tested enumeration scored `ship/SKILL.md` QUALIFIED while it still dispatched `skill: soleur:preflight`, and scored the very `soleur:trigger-cron` form that opened the issue QUALIFIED in three more skills. Its marker block contains `Skill tool` and `invokeSkill`, so the backfill made every obliged skill trigger-bearing *by the block*: leave-one-out went from 6/12 alternatives unreachable to **12/12**, and a single-alternative pattern reported all four floors green over a fully vacuous gate. Its auto-exempt "ceiling" was a net-count identity an add-one-delete-one PR satisfied exactly. Separately, appending the revision under `## v2 Guard Contract` did not match `lint-guard-contract.py`'s `^##\s+Guard\s+Contract\b`, so the lint validated only the **superseded** v1 contract and reported one entry for a file with two. See `knowledge-base/project/learnings/2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`.

**Reject conditions** (enforced mechanically by [lint-guard-contract.py](../../../../scripts/lint-guard-contract.py), and halted at deepen-plan Phase 4.11): the section missing while detection fires; a `## Guard Contract` heading with zero `### Guard` entries; a missing or placeholder `**Property.**` or `**Assembly.**`; a mutation matrix with fewer than 3 rows. The lint quantifies over EVERY entry, not the first.

**A guard over a script that writes into a user's tree carries an exit-site table by position relative to the FIRST write, and one row per precondition proving it resolves before that write.** "Cleans up on failure" is a property of that window, not of the failure arms the script names; a claim scoped to named codes is true and useless when the failure that fires is a different one. **Why:** #8288/PR #8352 — a merge-base 69 sat after five emits and before any trap; six review seats measured five files left and a 66 on every re-run. See `knowledge-base/project/learnings/2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md`.

**Skip silently** when the deliverable contains no guard — a copy change, a dependency bump, a pure refactor behind existing tests.

<!-- lint-infra-ignore start: describes a gate trigger / a past defect; prescribes no operator step (pre-existing on main, surfaced when #8301 staged this file) -->
**Why:** the preflight Check 10 execution-boundary work (merged 2026-08-10) absorbed FIVE adversarial review rounds; every round found real defects in the previous round's fixes, and ~20 findings reduced to the one class above. Instances: a mount-set closure assertion scoped to `BWRAP_ARGS=( … )` while `GIT_BIND`, `BWRAP_PROC` and the exec line also injected mounts (three separate one-line edits each re-opened the operator's credential surface with the whole suite green — verified against live bwrap reaching the Doppler token, `~/.ssh` and the gh token store); a parity floor counting ITERATIONS rather than distinct shapes; a suppression grep anchored on `test`/`it`/`describe`, which are rebindable; and an anti-vacuity gate with NO floor on its own dispatch. Those were not five discoveries — they were ONE enumeration nobody performed, found five times by different means, at ~880k subagent tokens and five CI cycles. The root cause was at plan time: that plan specified CONTROLS and 13 Test Scenarios all of the shape "command X -> terminal Y", and ZERO of the shape "mutation M -> guard G reddens". For a change whose deliverable WAS guards, the scenarios tested the thing being guarded. See `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.
<!-- lint-infra-ignore end -->

### 3. SpecFlow Analysis

**If soleur:product:spec-flow-analyzer was already invoked in Phase 2.5, skip this phase and proceed to Phase 4.**

After planning the issue structure, run SpecFlow Analyzer to validate and refine the feature specification. SpecFlow is especially valuable for CI/workflow and infrastructure changes where bash conditional logic can silently drop edge cases that human review misses.

- Task soleur:product:spec-flow-analyzer(feature_description, research_findings)

**SpecFlow Analyzer Output:**

- [ ] Review SpecFlow analysis results
- [ ] Incorporate any identified gaps or edge cases into the issue
- [ ] Update acceptance criteria based on SpecFlow findings

### 4. Choose Implementation Detail Level

**Read `plugins/soleur/skills/plan/references/plan-issue-templates.md` now** to load the three issue templates (MINIMAL, MORE, A LOT). Select the appropriate detail level based on complexity -- simpler is mostly better. Use the template structure from the reference file for the chosen level.

### 4.5. Scoped Advisor Consult (token-frugal)

Before finalizing the plan into issues, get one strong-model second opinion at the highest-leverage decision point — but pay only for a curated payload, not the whole session.

Spawn a **Task** subagent via `resolveAdvisorTier()` (semantic tier `advisor`; if that spawn is rejected because the org lacks the advisor-tier model, retry once with `resolveAdvisorFallback()` / semantic tier `strong`) and a **curated** prompt — pass only the plan's `## Overview`, `## Implementation Phases`, and the phase you judge riskiest. Do NOT pass the conversation: a Task subagent receives prompt text only (`knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`), so curation is the token lever that makes this far cheaper than Claude Code's built-in advisor (which re-sends the full transcript, uncached, every call). Prompt shape:

> Review this implementation plan's approach and its riskiest phase. Name the one or two changes most likely to prevent rework or a wrong-architecture commit. Be concise — assume you see only what is quoted. PLAN:\n<overview + phases + riskiest phase>

Apply the returned guidance before Step 5. Advisory only — do not block, loop, or re-consult. Skip silently in a resource-constrained run only if the plan is trivially mechanical (single-file, no architecture choice). Rationale + the `resolveAdvisorTier()` / semantic tier `advisor` upgrade-pin justification: ADR-083 (`knowledge-base/engineering/architecture/decisions/ADR-083-scoped-strong-model-consult-at-decision-gates.md`). Harness SKUs: ADR-110 (`plugins/soleur/lib/harness-model-map.ts`).

**When the consult and the session model agree the operator's *stated direction* should change** (drop/merge/split/add scope the operator specified), that is a **User-Challenge** per [decision-principles.md](../brainstorm-techniques/references/decision-principles.md) (ADR-084), not guidance to silently apply — the operator's direction is the default. Operator-attached: surface it at the post-`plan-review` confirmation gate with the 5-line frame. Headless (this Step runs inside a Task subagent under one-shot): do NOT ask — persist it to `knowledge-base/project/specs/<branch>/decision-challenges.md` for `ship` to render + file as an `action-required` issue.

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

### 6.5. Sharp Edges verification pass

**Read [plan-sharp-edges.md](./references/plan-sharp-edges.md) now, ONCE — the
plan file is complete (Acceptance Criteria land last, so this is the first
point at which there is a finished plan to check) — and apply it as a
verification pass over the plan before handing it to Plan Review.** It is a
~150 KB / ~58k-token catalogue of plan-writing traps, each written against a
concrete past failure; most entries (diff-scope ACs, census-over-enumeration,
universal-negative claims, verification commands that cannot fail) apply to
ANY plan, so the load is not conditional on the plan's shape. It sits here, at
the end of the run, deliberately: the Read tool pages it in three ~25k-token
pages, and a block loaded at turn k is re-sent on every turn after k — loading
it last is what keeps it off every earlier turn (ADR-229 records the ledger).
Read all three pages; the paging notice on page 1 is not the catalogue. **If
the file is not present, STOP and report that the plugin install is
incomplete**: a silently-absent catalogue is the ADR-151 failure mode this repo
has already paid for once.

## Plan Review (Always Runs)

After writing the plan file, automatically run `/plan_review <plan_file_path>` to get feedback from the reviewer panel in parallel:

- **Eng panel (always):** DHH Rails Reviewer (challenges overengineering), Kieran Rails Reviewer (correctness, convention), Code Simplicity Reviewer (YAGNI) — escalating to +soleur:engineering:review:architecture-strategist +soleur:product:spec-flow-analyzer at the single-user-incident threshold.
- **Named CEO/design/devex panel (relevance-gated):** `soleur:product:cpo`/`soleur:marketing:cmo` (business), `soleur:product:design:ux-design-lead` (design), `soleur:engineering:cto` (devex) — spawned only when the plan is relevant to the lens, by an independent content scan (see `plan-review/SKILL.md`). Their findings are frequently **taste**, so `plan-review` tags each consolidated decision `decisionClass ∈ {mechanical, taste, user-challenge}` per [decision-principles.md](../brainstorm-techniques/references/decision-principles.md) (ADR-084).

**After review completes**, present the consolidated feedback (agreements first, then disagreements), then apply by class:

1. **Mechanical** findings → auto-apply to the plan file (both modes). **Fail-closed default:** auto-apply *only* a decision **explicitly tagged `mechanical`**. Treat any decision that is **unclassified, ambiguous, or sourced from a named-panel (product/market/design/devex) finding** as **Taste** — surface it, never silently auto-apply. (The producer defaults named findings to Taste, but the consumer must not depend on producer-side tagging fidelity: an untagged decision on the prose path routes to surfacing, not to auto-apply.)
2. **Taste / User-Challenge** findings →
   - *Operator-attached* (real TTY): present at the "Apply these changes?" gate below (Yes / Partially / Skip); a **User-Challenge** uses the 5-line frame (the operator's stated direction is the default).
   - *Headless* (reuse the mode predicate at [`plan/SKILL.md` §Product/UX Gate step 4b, ":330"] — `HEADLESS_MODE`, no-TTY, `soleur:one-shot`, `--headless`, OR a plan-file-path arg): **do NOT pause.** Persist each Taste / User-Challenge to `knowledge-base/project/specs/<branch>/decision-challenges.md` (append), which `ship` Phase 6 renders into the PR body + files as an `action-required` issue. This converges with the Step 4.5 `decision-challenges.md` wiring (`:574`) onto one artifact.

**Operator-attached apply gate** (Mechanical already applied above):

1. Ask: "Apply these changes?" (Yes / Partially / Skip)
2. If Yes: apply all remaining (Taste/User-Challenge) changes to the plan file
3. If Partially: ask which changes to apply, then apply selected changes
4. If Skip: continue unchanged

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
   # Exact plan path, never the plans/ directory: a directory add sweeps abandoned skeletons from
   # earlier runs into this commit. PLAN is the path Phase 0.7 resolved; the :? guard fails loudly
   # rather than expanding to "" — `git add ""` aborts ATOMICALLY, which would silently drop
   # tasks.md from the same command and leave both artifacts untracked.
   : "${PLAN:?plan path unresolved — Phase 0.7 selector did not run}"
   git add "$PLAN" "knowledge-base/project/specs/${BR}/tasks.md"
   git commit -m "docs: create plan and tasks for ${BR}"
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
   All artifacts are on disk. Paste this to resume:

   soleur:work <plan-file-path>

   Context: branch <branch>, worktree <worktree-path>, PR #<N>, issue #<N>.
   <one-line summary of what was already done>
   ```

   Render the `soleur:<skill>` entry as the active harness's **operator-typed form** per `formatSkillInvocation` (`plugins/soleur/lib/harness.ts`) before printing — the operator types it into a fresh session where no routing contract is in context; no agent reads it.

   Replace placeholders with actual values from the session. The user must be
   able to paste the command and go without re-explaining context.

   **Whether to recommend `/clear` is evidence-based (#8323), not a fixed
   point in the workflow.** Prepend "Run `/clear` first, then paste this:"
   ONLY when this session carries a `SOLEUR_COMPACTION_DIRECTIVE` marker with
   `recommend=true` — `compaction-state.sh` injects it into
   `additionalContext` after the second automatic compaction of the current
   session window. The prompt itself is unconditional; it is the *nudge* that
   is conditional. A session that never compacted, a kill-switched hook
   (`SOLEUR_DISABLE_COMPACTION_HOOKS=1`) and a non-Claude harness all land in
   the no-marker branch, and emitting the prompt with no nudge is the correct
   output there rather than a degraded one.

**Resume prompt (MANDATORY):** After the display message above, always output a copy-pasteable resume prompt block. This is required by AGENTS.md whenever `/clear` is mentioned. Format:

```text
Resume prompt (copy-paste after /clear):
soleur:work <plan-path>. Branch: feat-<name>. Worktree: .worktrees/feat-<name>/. Issue: #<number>. PR: #<pr-number>. Plan reviewed, implementation next.
```

Render the `soleur:<skill>` entry as the active harness's **operator-typed form** per `formatSkillInvocation` (`plugins/soleur/lib/harness.ts`) before printing — the operator types it into a fresh session where no routing contract is in context; no agent reads it.

## Post-Generation Options

After plan review, use the **AskUserQuestion tool** to present these options:

**Resume prompt (MANDATORY — AGENTS.md Communication):** Before presenting the question, generate a copy-pasteable resume prompt containing: skill to run (`soleur:work`), plan file path, branch name, worktree path, PR number, issue number, and a one-line summary of what was already done. Display it in a fenced code block so the user can paste it into a fresh session after `/clear`. This is the single most important output of the post-generation phase — without it, the user cannot resume in a new session without re-explaining context.

**Question:** "Plan reviewed and ready at `knowledge-base/project/plans/YYYY-MM-DD-<type>-<name>-plan.md`. Context is saved to disk. What would you like to do next?" — append " Two automatic compactions have occurred, so `/clear` before `soleur:work` is recommended." only when a `SOLEUR_COMPACTION_DIRECTIVE` marker with `recommend=true` is present in this session (#8323). The unconditional "run `/clear` for maximum headroom" this replaces fired identically on a session with zero compactions and on one that had lost state twice, which is the whole defect.

**Options:**

1. **Open plan in editor** - Open the plan file for review
2. **Run `soleur:deepen-plan`** - Enhance each section with parallel research agents (best practices, performance, UI)
3. **Start `soleur:work`** - Begin implementing this plan locally
4. **Start `soleur:work` on remote** - Begin implementing in Claude Code on the web (use `&` to run in background)
5. **Create Issue** - Create issue in project tracker (GitHub/Linear)
6. **Simplify** - Reduce detail level

Based on selection:

- **Open plan in editor** → Run `open knowledge-base/project/plans/<plan_filename>.md` to open the file in the user's default editor
- **`soleur:deepen-plan`** → Call the soleur:deepen-plan command with the plan file path to enhance with research
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

This rule governs a plan that already has `## Acceptance Criteria`. A plan file lacking that section
was interrupted mid-run; Phase 0.7 continues it in place rather than duplicating or overwriting it.

**Archive completed plans:**
Run `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/project/plans/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "plan: archive <topic>"`.
