---
name: deepen-plan
description: "This skill should be used when enhancing an existing plan with parallel research agents for each section."
---

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/deepen-plan.workflow.js`](./workflows/deepen-plan.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Deepen Plan - Power Enhancement Mode

## Introduction

**Note: The current year is 2026.** Use this when searching for recent documentation and best practices.

This skill takes an existing plan (from the `soleur:plan` skill) and enhances each section with parallel research agents. Each major element gets its own dedicated research sub-agent to find:

- Best practices and industry patterns
- Performance optimizations
- UI/UX improvements (if applicable)
- Quality enhancements and edge cases
- Real-world implementation examples

The result is a deeply grounded, production-ready plan with concrete implementation details.

## Plan File

<plan_path> #$ARGUMENTS </plan_path>

**If the plan path above is empty:**

1. Check for recent plans: `ls -la knowledge-base/project/plans/`
2. Ask the user: "Which plan would you like to deepen? Please provide the path (e.g., `knowledge-base/project/plans/2026-01-15-feat-my-feature-plan.md`)."

Do not proceed until a valid plan file path is provided.

## Main Tasks

### 1. Parse and Analyze Plan Structure

<thinking>
First, read and parse the plan to identify each major section that can be enhanced with research.
</thinking>

**Read the plan file and extract:**

- [ ] Overview/Problem Statement
- [ ] Proposed Solution sections
- [ ] Technical Approach/Architecture
- [ ] Implementation phases/steps
- [ ] Code examples and file references
- [ ] Acceptance criteria
- [ ] Any UI/UX components mentioned
- [ ] Technologies/frameworks mentioned (Rails, React, Python, TypeScript, etc.)
- [ ] Domain areas (data models, APIs, UI, security, performance, etc.)

**Create a section manifest:**

```
Section 1: [Title] - [Brief description of what to research]
Section 2: [Title] - [Brief description of what to research]
...
```

### 2. Discover and Apply Available Skills

<thinking>
Dynamically discover all available skills and match them to plan sections. Don't assume what skills exist - discover them at runtime.
</thinking>

**Step 1: Discover ALL available skills from ALL sources**

```bash
# 1. Project-local skills (highest priority - project-specific)
ls .claude/skills/

# 2. User's global skills (~/.claude/)
ls ~/.claude/skills/

# 3. soleur plugin skills
ls ~/.claude/plugins/cache/*/soleur/*/skills/

# 4. ALL other installed plugins - check every plugin for skills
find ~/.claude/plugins/cache -type d -name "skills" 2>/dev/null

# 5. Also check installed_plugins.json for all plugin locations
cat ~/.claude/plugins/installed_plugins.json
```

**Important:** Check EVERY source. Don't assume soleur is the only plugin. Use skills from ANY installed plugin that's relevant.

**Step 2: For each discovered skill, read its SKILL.md to understand what it does**

```bash
# For each skill directory found, read its documentation
cat [skill-path]/SKILL.md
```

**Step 3: Match skills to plan content**

For each skill discovered:

- Read its SKILL.md description
- Check if any plan sections match the skill's domain
- If there's a match, spawn a sub-agent to apply that skill's knowledge

**Step 4: Spawn a sub-agent for EVERY matched skill**

**CRITICAL: For EACH skill that matches, spawn a separate sub-agent and instruct it to USE that skill.**

For each matched skill:

```
Task general-purpose: "You have the [skill-name] skill available at [skill-path].

YOUR JOB: Use this skill on the plan.

1. Read the skill: cat [skill-path]/SKILL.md
2. Follow the skill's instructions exactly
3. Apply the skill to this content:

[relevant plan section or full plan]

4. Return the skill's full output

The skill tells you what to do - follow it. Execute the skill completely."
```

**Spawn ALL skill sub-agents in PARALLEL:**

- 1 sub-agent per matched skill
- Each sub-agent reads and uses its assigned skill
- All run simultaneously
- 10, 20, 30 skill sub-agents is fine

**Each sub-agent:**

1. Reads its skill's SKILL.md
2. Follows the skill's workflow/instructions
3. Applies the skill to the plan
4. Returns whatever the skill produces (code, recommendations, patterns, reviews, etc.)

**Example spawns:**

```
Task general-purpose: "Use the dhh-rails-style skill at ~/.claude/plugins/.../dhh-rails-style. Read SKILL.md and apply it to: [Rails sections of plan]"

Task general-purpose: "Use the frontend-design skill at ~/.claude/plugins/.../frontend-design. Read SKILL.md and apply it to: [UI sections of plan]"

Task general-purpose: "Use the agent-native-architecture skill at ~/.claude/plugins/.../agent-native-architecture. Read SKILL.md and apply it to: [agent/tool sections of plan]"

Task general-purpose: "Use the security-patterns skill at ~/.claude/skills/security-patterns. Read SKILL.md and apply it to: [full plan]"
```

**No limit on skill sub-agents. Spawn one for every skill that could possibly be relevant.**

### 3. Discover and Apply Learnings/Solutions

<thinking>
Check for documented learnings from the `soleur:compound` skill. These are solved problems stored as markdown files. Spawn a sub-agent for each learning to check if it's relevant.
</thinking>

**LEARNINGS LOCATION - Check these exact folders:**

```
knowledge-base/project/learnings/           <-- PRIMARY: Project-level learnings (created by soleur:compound)
├── performance-issues/
│   └── *.md
├── debugging-patterns/
│   └── *.md
├── configuration-fixes/
│   └── *.md
├── integration-issues/
│   └── *.md
├── deployment-issues/
│   └── *.md
└── [other-categories]/
    └── *.md
```

**Step 1: Find ALL learning markdown files**

Run these commands to get every learning file:

```bash
# PRIMARY LOCATION - Project learnings
find docs/solutions -name "*.md" -type f 2>/dev/null

# If docs/solutions doesn't exist, check alternate locations:
find .claude/docs -name "*.md" -type f 2>/dev/null
find ~/.claude/docs -name "*.md" -type f 2>/dev/null
```

**Step 2: Read frontmatter of each learning to filter**

Each learning file has YAML frontmatter with metadata. Read the first ~20 lines of each file to get:

```yaml
---
title: "N+1 Query Fix for Briefs"
category: performance-issues
tags: [activerecord, n-plus-one, includes, eager-loading]
module: Briefs
symptom: "Slow page load, multiple queries in logs"
root_cause: "Missing includes on association"
---
```

**For each .md file, quickly scan its frontmatter:**

```bash
# Read first 20 lines of each learning (frontmatter + summary)
head -20 knowledge-base/project/learnings/**/*.md
```

**Step 3: Filter - only spawn sub-agents for LIKELY relevant learnings**

Compare each learning's frontmatter against the plan:

- `tags:` - Do any tags match technologies/patterns in the plan?
- `category:` - Is this category relevant? (e.g., skip deployment-issues if plan is UI-only)
- `module:` - Does the plan touch this module?
- `symptom:` / `root_cause:` - Could this problem occur with the plan?

**SKIP learnings that are clearly not applicable:**

- Plan is frontend-only -> skip `database-migrations/` learnings
- Plan is Python -> skip `rails-specific/` learnings
- Plan has no auth -> skip `authentication-issues/` learnings

**SPAWN sub-agents for learnings that MIGHT apply:**

- Any tag overlap with plan technologies
- Same category as plan domain
- Similar patterns or concerns

**Step 4: Spawn sub-agents for filtered learnings**

For each learning that passes the filter:

```
Task general-purpose: "
LEARNING FILE: [full path to .md file]

1. Read this learning file completely
2. This learning documents a previously solved problem

Check if this learning applies to this plan:

---
[full plan content]
---

If relevant:
- Explain specifically how it applies
- Quote the key insight or solution
- Suggest where/how to incorporate it

If NOT relevant after deeper analysis:
- Say 'Not applicable: [reason]'
"
```

**Spawn sub-agents in PARALLEL for all filtered learnings.**

**These learnings are institutional knowledge - applying them prevents repeating past mistakes.**

### 4. Launch Per-Section Research Agents

<thinking>
For each major section in the plan, spawn dedicated sub-agents to research improvements. Use the Explore agent type for open-ended research.
</thinking>

**For each identified section, launch parallel research:**

```
Task Explore: "Research best practices, patterns, and real-world examples for: [section topic].
Find:
- Industry standards and conventions
- Performance considerations
- Common pitfalls and how to avoid them
- Documentation and tutorials
Return concrete, actionable recommendations."
```

**Also use Context7 MCP for framework documentation:**

For any technologies/frameworks mentioned in the plan, query Context7:

```
mcp__plugin_soleur_context7__resolve-library-id: Find library ID for [framework]
mcp__plugin_soleur_context7__query-docs: Query documentation for specific patterns
```

**Verify API availability against installed SDK version:** Context7 docs may reference APIs not yet available in the project's pinned dependency version. After recommending a specific API (e.g., `getClaims()`), check `node_modules` or `Gemfile.lock` to confirm the method exists in the installed version before including it in the plan.

- When Context7 MCP returns Terraform resource attributes, cross-check against the installed provider version (`grep -A2 'registry.terraform.io/<provider>' .terraform.lock.hcl`). Context7 returns latest docs, not version-pinned docs — attributes may not exist in the pinned version.
- When the plan changes a tunable's **semantic** (reset trigger, scope, evaluation point — e.g., "fires once per turn" → "resets per block"; "absolute" → "rolling"), `grep -rn "<tunable-name>" test/` and audit EVERY matching test file in the test-compatibility section — never sample a subset. Sampling lets at least one test that pinned the old semantic survive into the green-suite claim, surfacing the gap as a broken GREEN run mid-implementation. **Why:** PR #3225 — deepen-pass listed AC7/AC8/AC9/AC17/silent-fallback as compatible with the new "any-block resets" runaway semantic but did not enumerate the Stage 2.2 secondary-trigger test in `soleur-go-runner.test.ts`, which used `wallClockTriggerMs: 30_000` + multiple tool_uses and asserted the OLD "30s from first tool_use" contract. Test broke at GREEN time and required updating mid-implementation. See `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.

**Use WebSearch for current best practices:**

Search for recent (2024-2026) articles, blog posts, and documentation on topics in the plan.

### 4.4. Precedent-Diff Gate (Pattern-bound Behaviors)

When the plan section prescribes **pattern-bound behaviors** with sibling-precedent files in the same repo — (a) SQL function definitions with `SECURITY DEFINER`/`INVOKER`, (b) atomic write sequences (open/write/rename/fsync), (c) lock acquisition or mutex patterns, (d) RPC permissioning, (e) connection-pool tuning, (f) circuit-breaker shapes, or (g) any other shape where the codebase has established a canonical form — `git grep` for the precedent and produce a side-by-side diff in the plan's "Risks & Mitigations" section. If no precedent exists, the plan must explicitly note "no precedent; pattern is novel" so reviewers know to scrutinize. **Why:** PR #2954 — initial plan prescribed `SECURITY INVOKER` for a v1→v2 BYOK migration RPC; deepen-plan caught and corrected to `SECURITY DEFINER` via precedent migration 027. Same PR: atomic-write missing `fdatasync` between write and close; deepen-plan added it after grepping for prior atomic-write call sites. See `knowledge-base/project/learnings/best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`. Plan-skill counterpart: `precedent-diff is enforced at deepen-plan` (forward-pointer).

#### Scheduled-work pattern check

When the plan introduces a new scheduled job (recurring task, cron, polling loop), check the canonical pattern BEFORE proposing the trigger mechanism. Run:

```bash
git ls-files | grep -E "apps/web-platform/server/inngest/functions/cron-" | head -3
git ls-files | grep -E "^\.github/workflows/scheduled-" | wc -l
```

If the Inngest cron functions count is > 0, propose the scheduled job as an Inngest function under `apps/web-platform/server/inngest/functions/cron-*.ts` — NOT as a `.github/workflows/scheduled-*.yml` workflow. The Inngest path is canonical per ADR-033.

GH Actions cron is acceptable ONLY when (a) the work is purely git/repo-scoped (no app context, no app secrets, no Sentry integration) AND (b) the work could not benefit from `step.run` memoization / Inngest replay. When in doubt, prefer Inngest.

**Why:** PR #4452 shipped `scheduled-stale-deferred-scope-outs.yml` as GH Actions cron and was immediately migrated to Inngest in PR #4457 because the work properly belongs in Inngest. The precedent-check at plan time would have caught this; the post-implementation review almost missed it. The `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` PreToolUse hook is the mechanical second-net.

### 4.45. Round-1 Implementation-Realism Passes

After Phase 4 spawns per-section research agents, fan out two additional agent passes in the same parallel batch:

1. **Verify-the-negative pass.** For every negative security claim in the plan body (regex: `NEVER|MUST NOT|does not reach|cannot leak|is not exposed`), spawn a targeted agent task: "grep the named/implied implementation file for the constrained behavior; report `contradicts | confirms | not-applicable` with file:line citation." This catches "the field is not exposed to clients" claims that contradict a `process.env.NEXT_PUBLIC_*` site one grep away.
2. **Post-edit self-audit pass.** After round-1 edits drop or rename infrastructure (tables, columns, modules), spawn a re-read pass that greps the plan body for references to dropped symbols. Every hit is a candidate for a downstream rewrite that round 1 missed (e.g., `tenant_cost_window` ON CONFLICT after the table was dropped).

Tier advisory (ADR-053): spawn both passes with the Agent tool's `model: sonnet` — they are pure grep sweeps with ternary verdicts (the most mechanical Task spawns in the plugin), so the session's top tier adds cost without recall. Per-section research agents and the merge pass stay on the session model.

**Why:** PR #3240 deepen-pass for `feat-agent-runtime-platform` showed two round-1 misses (BYOK process.env contradiction; `tenant_cost_window` ON CONFLICT after table-drop) that round 2 caught only because the user re-invoked the skill. Folding both passes into round 1 closes the loop without requiring a second user invocation. See `knowledge-base/project/learnings/best-practices/2026-05-05-deepen-pass-round-2-implementation-realism-vs-round-1-structural.md`.

### 4.5. Network-Outage Deep-Dive (Conditional)

If the plan's Overview, Problem Statement, or Hypotheses contain any of the trigger patterns `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive), read `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` and spawn a dedicated "Network-Outage Deep-Dive" research agent in parallel with the other deepen agents.

**Resource-shape trigger (implicit SSH dependency).** Also fire this gate when the plan drives `terraform apply` (with or without `-target=`) on any resource whose definition contains `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block. The provisioner block makes SSH a hard apply-time dependency that the prose-only keyword scan won't detect — the plan body need not mention SSH at all and apply still fails on `connection reset by peer` if the operator's egress IP has drifted out of the firewall allowlist. **Why:** #3061 — plan body had zero SSH keywords; apply on `terraform_data.deploy_pipeline_fix` (file+remote-exec provisioners) still hit a handshake reset because Phase 4.5 didn't fire.

The deep-dive agent's task:

1. Read the checklist in full.
2. For each of the four layers (L3 firewall allow-list, L3 DNS/routing, L7 TLS/proxy if HTTPS, L7 application), verify the plan's Hypotheses section cites a concrete verification artifact (CLI output, log excerpt, or explicit "not verified" note).
3. Emit a "Network-Outage Deep-Dive" subsection in the plan with the layer-by-layer verification status and any gaps that need closing before implementation.

Per AGENTS.md `hr-ssh-diagnosis-verify-firewall`, plans addressing SSH/network-connectivity symptoms MUST verify the L3 firewall allow-list against current client egress IP BEFORE proposing service-layer fixes. The deep-dive is the deepen-plan enforcement layer.

When a trigger pattern matches, emit rule-application telemetry so the weekly aggregator records the deepen-plan enforcement layer fired (see AGENTS.md `hr-ssh-diagnosis-verify-firewall`):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-ssh-diagnosis-verify-firewall applied \
  "When a plan addresses an SSH/network-connectivity s"
```

### 4.55. Downtime & Cutover Halt — Zero-Downtime-First (Conditional)

Soleur users are a live single-operator surface; an unexpected outage of the web/Concierge platform is a `single-user incident` (brand-survival). So a plan whose change would take a serving surface offline MUST **default to a zero-downtime cutover** and prove it in the plan — not treat downtime as the baseline.

**Trigger — fire when the plan's Files-to-Edit or Overview implies a downtime-inducing operation.** Any of:
- **Infra reboot/replace class:** a change to a running host that Hetzner/the provider applies via power-off or replace — `placement_group_id` attach, `server_type`/`location`/`datacenter` change, a `-/+`/`must be replaced` on any `hcloud_server`/volume/attachment, or a singleton→`for_each`/cluster cutover of a serving resource. (Attributes the serving host pins via `lifecycle { ignore_changes = [...] }` — e.g. `image`, `user_data` on `hcloud_server.web` — do NOT trigger, since the provider ignores them on the running host.)
- **Database lock class:** a migration with lock-taking or table-rewriting DDL on a hot table — `ALTER TABLE … ADD COLUMN … NOT NULL DEFAULT` (rewrite), `ALTER COLUMN … TYPE`, a non-`CONCURRENTLY` index, `ADD CONSTRAINT` without `NOT VALID`, or a backfill that holds a long transaction.
- **Deploy/router class:** a change that drops in-flight requests — a single-host container swap without drain, a tunnel/router restructure, a connector restart on the sole serving connector.

**Rule.** On trigger, the plan MUST contain a `## Downtime & Cutover` section that (1) names the exact offline-inducing operation and the surface it affects, (2) evaluates a **zero-downtime path** — blue-green (provision the new resource fresh, drain, cut over, retire the old), rolling, expand-contract (add-nullable → backfill → enforce → drop-old), `terraform state mv`/state-only re-address, `CREATE INDEX CONCURRENTLY`, drain-then-act — and **defaults to it**, and (3) accepts residual downtime ONLY with an explicit justification + a **bounded maintenance window** + operator sign-off. HALT if the trigger fires and the section is absent or is boilerplate (no concrete cutover mechanism, no per-stage verification/rollback). This is the deepen-plan companion to Phase 4.6 (user-brand impact) and 4.5 (network-outage), scoped to availability during the change itself.

Emit telemetry when the gate fires (records the enforcement layer for the weekly aggregator, mirroring the sibling halts 4.5/4.6; reuses the brand-survival rule this gate invokes):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-weigh-every-decision-against-target-user-impact applied \
  "Downtime & Cutover halt: plan must default to a zero-"
```

**Why:** #5887 — a `moved`-block migration was framed as a rebooting full `terraform apply`; the actual wedge cleared with a **zero-downtime `terraform state mv`** (state-only re-address, no reboot), and the real web-2 cutover is blue-green (a fresh host is born into the placement group with no reboot; only the old host needs a power-off, done while drained). The rebooting path was the *default* only because no gate forced a zero-downtime evaluation first. See `knowledge-base/project/learnings/2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md`.

### 4.6. User-Brand Impact Halt (Always)

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every plan MUST contain a `## User-Brand Impact` section before deepen-plan can proceed. This phase is a hard gate — no deepen agents fan out until the section exists and contains concrete content.

**Step 1 — Locate the section.** Grep the target plan file:

```bash
grep -q '^## User-Brand Impact' <plan-file>
```

If the heading is absent, HALT with:

> Error: Plan is missing `## User-Brand Impact` section.
> See `plugins/soleur/skills/plan/references/plan-issue-templates.md` for the template.
> Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every plan
> must answer the user-impact framing question before deepen-plan can proceed.
> Re-run `/soleur:plan` (or edit the plan directly) to add the section, then re-run deepen-plan.

**Step 2 — Validate the body.** If the heading exists, extract the section body (everything between `^## User-Brand Impact` and the next `^##` heading). Reject the section as non-compliant if ANY of:

- The body is empty (only whitespace between headings).
- Every bullet contains only `TBD`, `TODO`, `N/A`, `<placeholder>`, or single-word stubs.
- The threshold line is missing or the value is not one of `none`, `single-user incident`, or `aggregate pattern`.
- The threshold is `none` AND the diff (or referenced `Files to edit` list) matches the canonical sensitive-path regex (single source of truth — kept in sync with `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1):

  ```bash
  SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'
  ```

  AND no `threshold: none, reason: <one-sentence>` scope-out bullet (with a non-empty reason) is present in the section.

On rejection, HALT with the same error message as Step 1, replacing the first line with the specific failure (`empty body`, `placeholder content`, `missing threshold`, `none-threshold without scope-out`).

**Step 3 — Emit telemetry.** When the halt fires (Step 1 OR Step 2), emit rule-application telemetry so the weekly aggregator records the deepen-plan enforcement layer fired:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-weigh-every-decision-against-target-user-impact applied \
  "Every plan/PR touching credentials, auth, data, paym"
```

**Step 4 — Pass-through.** If the section is present, non-empty, has a valid threshold, and (when `none`) has a scope-out line for sensitive-path diffs, deepen-plan proceeds normally. No telemetry is emitted on pass — the gate only records when it activates.

**Why:** The framing layer (brainstorm Phase 0.1) and the template layer (plan Phase 2.6) can both be skipped or filled with placeholders. This phase is the load-bearing pre-implementation gate that catches both — a plan with an empty section cannot pass deepen-plan, which means it cannot proceed to `/work`. Combined with preflight Check 6 (ship-time gate) and the `user-impact-reviewer` conditional agent (review-time gate), this closes the workflow loop introduced for #2887.

### 4.7. Observability Gate Verification (Always)

Per AGENTS.md `hr-observability-as-plan-quality-gate`, every plan whose Files-to-Edit touches production code/infra (per plan Phase 2.9 trigger set) MUST contain a `## Observability` section with the 5-field schema. Symmetric to Phase 4.6 above; this gate is what makes plan Phase 2.9 load-bearing.

**Step 1 — Detect trigger.** Inspect the plan's `## Files to Edit` (or equivalent) list. If every path matches one of:

- `^knowledge-base/`
- `^docs/`
- `^README\.md$`
- `^CHANGELOG\.md$`
- `\.md$` outside `plugins/*/skills/` and `apps/*/`

then the plan is pure-docs — skip silently (no further checks).

Otherwise the gate applies; proceed to Step 2.

**Step 2 — Locate the section.** Grep the target plan file:

```bash
grep -q '^## Observability' <plan-file>
```

If absent, HALT with:

> Error: Plan touches production code/infra but is missing `## Observability` section.
> See `plugins/soleur/skills/plan/references/plan-issue-templates.md` for the schema.
> Per AGENTS.md `hr-observability-as-plan-quality-gate`, every plan that ships production
> code or infrastructure must declare its observability surface before deepen-plan proceeds.

**Step 3 — Validate field values.** Extract the section body (between `^## Observability` and the next `^## ` heading). For each of the 5 required top-level fields (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`), reject if ANY of:

- **Field key absent** — `grep -qE "^\s*<field>:" <body>` returns no match.
- **Field value is a placeholder** — the field-value line (case-insensitive) matches `^\s*<field>:\s*(TODO|TBD|N/A|placeholder|manual operator check)\s*$` (anchored — distinguish "field is exactly this string" from "prose contains this string"). Also reject `^\s*<field>:\s*(TODO|TBD|N/A|placeholder|manual operator check)\b` — trailing whitespace + extra text still counts as a placeholder.
- **Field is empty / has no children** — for fields that template as a YAML block (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`), the line immediately following `<field>:` MUST be either a continuation (indented sub-field starting with whitespace + non-`#` content) OR an inline scalar value on the same line as the key. A bare `<field>:` followed by a blank line or another top-level key fails the gate. This is the empty-key case (#4116 review). Detect with: locate the `<field>:` line; if `awk "NR==<n>+1 {print}"` returns a blank line OR a line matching `^[^[:space:]]`, reject.
- **`discoverability_test.command` requires SSH** — extract the `command:` sub-field's value and reject if it matches `(^|\s|/)ssh(\s|$)` (word-boundary `ssh` followed by whitespace, end-of-string, or a path-style `/usr/bin/ssh`). Distinguishes the verb from `ssh-free` / `xssh` / `ssh.md` prose.

On rejection, HALT with a message naming the specific field and its failure mode (e.g., `"Phase 4.7 reject: liveness_signal is empty (no sub-fields and no inline value)"`).

**Step 4 — Emit telemetry.** When the halt fires (Step 2 OR Step 3), emit:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-observability-as-plan-quality-gate applied \
  "Every plan touching production code/infra MUST declar"
```

**Step 5 — Pass-through.** If the section is present, all 5 fields exist with non-placeholder values, no field is empty, and `discoverability_test.command` does not require SSH, deepen-plan proceeds normally. No telemetry on pass.

**Why:** #4116 — `inngest-heartbeat.service` was silently broken for 16+ hours because the substrate (introduced in #4085) declared no observability surface and the operator never had a non-SSH way to verify the heartbeat. Combined with plan Phase 2.9 (template-time gate), this phase is the load-bearing pre-implementation gate. The empty-key reject was added per the PR #4123 review — the most common drift mode is `liveness_signal:` with no children, which earlier regex-only forms allowed through.

### 4.8. PAT-Shaped Variable Halt (Always)

Per AGENTS.md `hr-github-app-auth-not-pat`, plans that introduce or reference a PAT-shaped TF variable, env var, or literal-format token for infra-time GitHub writes MUST be halted at deepen-plan time. App auth (App ID + installation_id + PEM) supersedes PAT across the board — Apps don't expire, don't require per-operator minting, and survive operator handoff.

**Step 1 — Trigger.** Always runs. The detection only fires on match; no opt-out.

**Step 2 — Grep the plan.** Run the following regex sweep against the plan file (case-insensitive):

```bash
PLAN="<plan-file>"
HITS=$(grep -niE '\bvar\.(github_actions_token|github_token|gh_token|gh_pat|github_pat|actions_token|installation_token|repo_token)\b|\bTF_VAR_(GITHUB|GH)_(TOKEN|PAT|AUTH)\b|\bvar\.[a-z_]*_(pat|token)\b|\b(ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82,})\b' "$PLAN" || true)
```

The four patterns target distinct PAT shapes:

- Named `var.*_token`/`var.*_pat` Terraform variables — covers the specific name eliminated in #4144 plus common rename shapes (`github_token`, `gh_pat`, `installation_token`, etc.).
- `TF_VAR_(GITHUB|GH)_(TOKEN|PAT|AUTH)` (case-insensitive) — the env-var form Doppler `--name-transformer tf-var` produces.
- `var.*_(pat|token)` — any plan variable suffixed `_pat` or `_token` (catches `var.gh_pat`, `var.org_token`, etc.).
- Literal token shapes — classic 40-char `ghp_<40>` and fine-grained `github_pat_<82+>`. The placeholder form `ghp_XXX...` is allowed; only literal-shape tokens reject.

**Step 3 — HALT on match.** If `HITS` is non-empty, emit:

> Error: Plan references PAT-shaped variable or literal. Use GitHub App auth (App ID + installation_id + pem_file via the `integrations/github` provider's `app_auth` block) per AGENTS.md `hr-github-app-auth-not-pat`. The `soleur-ai` GitHub App (App ID `3261325`) is provisioned and the discovery script is at `apps/web-platform/infra/scripts/get-app-installation-id.sh`. Apps don't expire, don't require per-operator minting, and survive operator handoff.
>
> Matches:
> $HITS

Halt deepen-plan; do NOT proceed to Phase 5.

**Step 4 — Emit telemetry.** When the halt fires, emit:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident hr-github-app-auth-not-pat applied \
  "Infra/CI GitHub writes auth via GitHub App, never PAT"
```

**Step 5 — Pass-through.** If no PAT-shaped patterns match, deepen-plan proceeds normally. No telemetry on pass.

**Why:** #4144 — PR-H #4066 added `var.github_actions_token` as a required TF variable, then never populated it in Doppler. Every `Apply deploy-pipeline-fix.yml` run since 2026-05-19T21:41Z failed before `terraform plan` could evaluate, blocking the entire deploy pipeline for ~14h (sudoers entry never refreshed → deploy webhook errored at `sudo: deploy : command not allowed` → Inngest heartbeat went silently red). The first defense is at plan-write time: catch PAT-shaped variables before they reach a workflow YAML.

### 4.9. UI-Wireframe Artifact Halt (Conditional)

Per `wg-ui-feature-requires-pen-wireframe`, a plan touching a UI surface must reference a committed `.pen` wireframe — otherwise the design phase silently shipped without one. This is the deepen-plan verifier on the one-shot path (one-shot chains plan→deepen-plan and skips brainstorm), mirroring the Phase 4.6/4.7 halts.

**Step 1 — Trigger.** Fires only when the plan touches a UI surface. Match the plan's `## Files to Edit` and `## Files to Create` against the shared UI-surface term list + glob superset (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`). No UI-surface file → skip silently (pass-through).

**Step 2 — Grep for a committed `.pen` reference.** On a UI-surface plan, grep the plan body for a wireframe-artifact reference and confirm it is committed:

```bash
PLAN="<plan-file>"
PEN=$(grep -oE 'knowledge-base/product/design/[A-Za-z0-9/_-]+\.pen' "$PLAN" | sort -u || true)
COMMITTED=""
for p in $PEN; do git ls-files --error-unmatch "$p" >/dev/null 2>&1 && COMMITTED="$COMMITTED $p"; done
```

**Step 3 — HALT on absence.** If the plan touches a UI surface but `COMMITTED` is empty, emit:

> Error: Plan touches a UI surface but references no committed `.pen` wireframe. Wireframes are a non-skippable deliverable (`wg-ui-feature-requires-pen-wireframe`) — run the producer (brainstorm Phase 3.55 or plan Phase 2.5; Pencil auto-installs via `pencil-setup --auto`), commit the `.pen` under `knowledge-base/product/design/{domain}/`, and reference it in the plan FRs. No Markdown/ASCII fallback.

Halt deepen-plan; do NOT proceed to Phase 5.

**Step 4 — Emit telemetry.** When the halt fires:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident wg-ui-feature-requires-pen-wireframe applied \
  "UI feature must ship a committed .pen wireframe, never skipped"
```

### 4.10. Encryption Posture Halt (Conditional)

Symmetric to Phase 4.7 above; this gate is what makes plan Phase 2.11 load-bearing. Fires only when the plan introduces a persistent data store or a new cross-component/network connection.

**Step 1 — Trigger.** Fires when the plan's `## Files to Edit` / `## Files to Create` match one of `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`, OR the plan prose names a store class (volume, database, bucket, queue, cache, backup target, log sink) or a new cross-component connection. No match on any of the above → skip silently (pass-through).

**Step 2 — Locate the section.** Grep the target plan file:

```bash
grep -q '^## Encryption Posture' <plan-file>
```

If absent, HALT with:

> Error: Plan introduces a persistent store or cross-component connection but is missing `## Encryption Posture` section.
> See `plugins/soleur/skills/plan/references/plan-issue-templates.md` for the schema.
> Every new store or connection must declare a design-time encryption posture before deepen-plan proceeds.

**Step 3 — Validate field values.** Extract the section body (between `^## Encryption Posture` and the next `^## ` heading). For each `at_rest` entry (`mechanism`, `evidence`, `defends_against`, `does_not_defend`, `disclosed_as`, `live_verification`) and each `in_transit` entry (`tls`, `cert_verification`, `does_not_defend`, `disclosed_as`), reject if ANY of:

- **Field key absent or empty** — the field is required by the schema (`encryption-posture-ledger.schema.json`, repo-root `scripts/`) and either has no key or matches `^\s*<field>:\s*(TODO|TBD|N/A|placeholder)\s*$`.
- **`mechanism` (or `at_rest` prose) matches the boilerplate ban-list** — case-insensitive: `provider handles`, `handled by the provider`, `encrypted by default` with no named attestation, `supports TLS`. These describe the absence of a posture, not a posture.
- **`does_not_defend` is empty, `none`, or `n/a`.** The field is mandatory — a reviewer judges the semantic content, not a regex; do NOT reject on wording similarity to `defends_against` (a verbatim-restatement check was considered and deleted — a vacuous grep for a semantic property).
- **An `exception` block is present but missing `tracking_issue` or `expires_on`.** An `exception` is required whenever `mechanism` is `plaintext-exception` or `cert_verification` is `off`; its absence in that case is itself a reject (folds into the field-key-absent case above).

On rejection, HALT with a message naming the specific field and its failure mode (e.g., `"Phase 4.10 reject: at_rest[0].does_not_defend is empty"`).

**Step 4 — Emit telemetry.** When the halt fires (Step 2 OR Step 3), emit:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident encryption-posture-design-time-default applied \
  "Every new store/connection MUST declare a verified encryption posture at plan time"
```

**Step 5 — Pass-through.** If the section is present, all required fields exist with non-boilerplate values, `does_not_defend` is non-empty, and every `exception` block carries both `tracking_issue` and `expires_on`, deepen-plan proceeds normally. No telemetry on pass.

**Why:** ADR-139 and `knowledge-base/project/plans/2026-07-23-feat-encryption-posture-design-time-default-plan.md` (Plan Review Revisions R1-R11). A declaration-only gate without Layer A (`lint-encryption-posture.py`, repo-root `scripts/`, resolving every citation against real code) and Layer B (live provider/host reconciliation) reproduces #6588 exactly — legal docs declared LUKS while the volume was plaintext ext4. This deepen-plan halt is the design-time half; it stops an underspecified or boilerplate posture from ever reaching `/work`.

**Step 5 — Pass-through.** Non-UI plan, or a committed `.pen` present → proceed normally. No telemetry on pass.

**Why:** #4819 — the one-shot path skips brainstorm, so plan Phase 2.5 is the sole producer; this halt is the independent verifier that a UI feature did not reach implementation with zero wireframes (the silent-skip class the feature kills).

### 5. Discover and Run ALL Review Agents

<thinking>
Dynamically discover every available agent and run them ALL against the plan. Don't filter, don't skip, don't assume relevance. 40+ parallel agents is fine. Use everything available.
</thinking>

**Step 1: Discover ALL available agents from ALL sources**

```bash
# 1. Project-local agents (highest priority - project-specific)
find .claude/agents -name "*.md" 2>/dev/null

# 2. User's global agents (~/.claude/)
find ~/.claude/agents -name "*.md" 2>/dev/null

# 3. soleur plugin agents (all subdirectories)
find ~/.claude/plugins/cache/*/soleur/*/agents -name "*.md" 2>/dev/null

# 4. ALL other installed plugins - check every plugin for agents
find ~/.claude/plugins/cache -path "*/agents/*.md" 2>/dev/null

# 5. Check installed_plugins.json to find all plugin locations
cat ~/.claude/plugins/installed_plugins.json

# 6. For local plugins (isLocal: true), check their source directories
# Parse installed_plugins.json and find local plugin paths
```

**Important:** Check EVERY source. Include agents from:

- Project `.claude/agents/`
- User's `~/.claude/agents/`
- soleur plugin (but SKIP engineering/workflow/ agents - only use review, research, and design)
- ALL other installed plugins (agent-sdk-dev, frontend-design, etc.)
- Any local plugins

**For soleur plugin specifically:**

- USE: `agents/engineering/review/*` (all reviewers)
- USE: `agents/engineering/research/*` (all researchers)
- USE: `agents/engineering/design/*` (design agents)
- SKIP: `agents/engineering/workflow/*` (workflow orchestrators, not reviewers)

**Step 2: For each discovered agent, read its description**

Read the first few lines of each agent file to understand what it reviews/analyzes.

**Step 3: Launch ALL agents in parallel**

For EVERY agent discovered, launch a Task in parallel:

```
Task [agent-name]: "Review this plan using your expertise. Apply all your checks and patterns. Plan content: [full plan content]"
```

**CRITICAL RULES:**

- Do NOT filter agents by "relevance" - run them ALL
- Do NOT skip agents because they "might not apply" - let them decide
- Launch ALL agents in a SINGLE message with multiple Task tool calls
- 20, 30, 40 parallel agents is fine - use everything
- Each agent may catch something others miss
- The goal is MAXIMUM coverage, not efficiency

**Step 4: Also discover and run research agents**

Research agents (like `best-practices-researcher`, `framework-docs-researcher`, `git-history-analyzer`, `repo-research-analyst`) should also be run for relevant plan sections.

### 6. Wait for ALL Agents and Synthesize Everything

<thinking>
Wait for ALL parallel agents to complete - skills, research agents, review agents, everything. Then synthesize all findings into a comprehensive enhancement.
</thinking>

**Collect outputs from ALL sources:**

1. **Skill-based sub-agents** - Each skill's full output (code examples, patterns, recommendations)
2. **Learnings/Solutions sub-agents** - Relevant documented learnings from `soleur:compound`
3. **Research agents** - Best practices, documentation, real-world examples
4. **Review agents** - All feedback from every reviewer (architecture, security, performance, simplicity, etc.)
5. **Context7 queries** - Framework documentation and patterns
6. **Web searches** - Current best practices and articles

**For each agent's findings, extract:**

- [ ] Concrete recommendations (actionable items)
- [ ] Code patterns and examples (copy-paste ready)
- [ ] Anti-patterns to avoid (warnings)
- [ ] Performance considerations (metrics, benchmarks)
- [ ] Security considerations (vulnerabilities, mitigations)
- [ ] Edge cases discovered (handling strategies)
- [ ] Documentation links (references)
- [ ] Skill-specific patterns (from matched skills)
- [ ] Relevant learnings (past solutions that apply - prevent repeating mistakes)

**Deduplicate and prioritize:**

- Merge similar recommendations from multiple agents
- Prioritize by impact (high-value improvements first)
- Flag conflicting advice for human review
- Group by plan section

### 7. Enhance Plan Sections

<thinking>
Merge research findings back into the plan, adding depth without changing the original structure.
</thinking>

**Enhancement format for each section:**

```markdown
## [Original Section Title]

[Original content preserved]

### Research Insights

**Best Practices:**
- [Concrete recommendation 1]
- [Concrete recommendation 2]

**Performance Considerations:**
- [Optimization opportunity]
- [Benchmark or metric to target]

**Implementation Details:**
```[language]
// Concrete code example from research
```

**Edge Cases:**

- [Edge case 1 and how to handle]
- [Edge case 2 and how to handle]

**References:**

- [Documentation URL 1]
- [Documentation URL 2]

```

### 8. Add Enhancement Summary

At the top of the plan, add a summary section:

```markdown
## Enhancement Summary

**Deepened on:** [Date]
**Sections enhanced:** [Count]
**Research agents used:** [List]

### Key Improvements
1. [Major improvement 1]
2. [Major improvement 2]
3. [Major improvement 3]

### New Considerations Discovered
- [Important finding 1]
- [Important finding 2]
```

### 9. Update Plan File

**Write the enhanced plan:**

- Preserve original filename
- Add `-deepened` suffix if the user prefers a new file
- Update any timestamps or metadata

## Output Format

Update the plan file in place (or if user requests a separate file, append `-deepened` after `-plan`, e.g., `2026-01-15-feat-auth-plan-deepened.md`).

## Quality Checks

Before finalizing:

- [ ] All original content preserved
- [ ] Research insights clearly marked and attributed
- [ ] Code examples are syntactically correct
- [ ] Links are valid and relevant
- [ ] No contradictions between sections
- [ ] Explicit string literals (error messages, log strings, Sentry messages, feature flags) match across Helper Contract / Acceptance Criteria / Test Scenarios / Test Implementation Sketch. Verbatim-preserved strings (e.g., for dashboard/alert continuity) are the highest-risk drift class — grep the whole plan for each quoted literal and confirm one canonical value.
- [ ] Every cited external SHA, tag, release version, or commit reference has been **resolved live** via `gh api` or an equivalent authoritative source in the same deepen pass — never cite SHAs from memory or training data. Show the command + output in a fenced block next to the claim. **Why:** In the #2540 plan, the fallback SHA for `claude-code-action@v1.0.100` was cited as `8a953ded...` (actually the `v1` floating tag), and `scheduled-roadmap-review.yml` was described as using `@v1` floating ref when it's actually a pinned SHA `@ff9acae5... # v1`. Both errors survived into the plan and were caught only in review.
- [ ] When a plan asserts "SHA pin X is in active use across N workflows" as evidence for adopting that pin, verify with **exact-match-and-count** (length-pinned), NOT `git grep -l '<sha>'` alone. `git grep -l` matches by literal substring, so a truncated SHA appears as a hit for any full-length SHA sharing the prefix — the verification is structurally blind to truncation of the value being verified. Cheapest gate: `git grep -hE 'uses: <action>@[0-9a-f]+' <scope> | awk -F@ '{print $2}' | awk '{print $1}' | sort -u` and assert every entry is exactly 40 chars. Plans citing SHAs MUST also quote the expected length (`# v4, 40-char SHA`). **Why:** PR #3893 — plan body shipped `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c` (37 chars, missing trailing `47c`) in both AC9 and Reference Implementation; deepen "5 in active use" check used `git grep -l` and prefix-matched the canonical 40-char pin, false-passing the verification. Three review agents (git-history-analyzer, pattern-recognition-specialist, security-sentinel) independently flagged P1 post-implementation. See `knowledge-base/project/learnings/2026-05-16-sha-pin-prefix-match-false-positive-in-plan-verification.md`.
- [ ] For any bash test scenario that claims "bad input is caught by \<operator\>", verify the operator's behavior under `set -euo pipefail`. Common operators that CRASH instead of catch under strict mode: `-gt`/`-lt`/`-eq` on non-numeric RHS, `$(( ))` on non-numeric, `${var?}` when var is unset. If the claim depends on catching, the plan must prescribe a preceding regex/emptiness guard. **Why:** PR #2716 T10 asserted "malformed TASKS row caught by threshold comparison" — under `set -e`, `[[ $n -gt $malformed ]]` crashed the whole step; caught in QA, fixed with explicit `[[ "$max_gap_days" =~ ^[0-9]+$ ]]` guard. See `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md`.
- [ ] Every cited PR or issue number (`#N` in plan prose, frontmatter `related_prs:`, learning Related sections) is verified live via `gh pr view N --json state,title` (or `gh issue view N --json state,title`) AND `git log --grep="#N"` confirms the cited work touches the files/areas claimed — never cite numbers from memory or training data. SHA/tag verification (above) does not cover plain PR-number citations whose narrative claim ("PR #N introduced X") can be wrong even when the PR exists. **Why:** PR #3295 plan attributed archive-trigger slot-release work to #3219; `git log --grep="#3219"` showed zero commits touching slot/sweep logic — actual precedent was #3217 (commit `d4858aba`, migration 036). Caught only at multi-agent review; corrected across plan + learning + frontmatter. See `knowledge-base/project/learnings/bug-fixes/2026-05-05-cc-stuck-active-conversation-leaks-slot.md` Session Error #1.
- [ ] Every plan-body **attribution claim** (cited commit hash, "X was reverted/added by PR #N", "current `<file>` contains/lacks `<pattern>`") is probed against `main`: `git rev-parse <hash>` + `git merge-base --is-ancestor <hash> main` for hashes; `git show main:<file> | grep -E '<pattern>'` for content claims; `gh pr view N --json files` for "PR added/removed file" claims. PR/issue STATE checks (above bullet) do NOT cover ATTRIBUTION; an attribution claim can be wrong while the cited PR is genuinely MERGED. **Why:** PR #3850 plan Sharp Edge claimed "PR #2734 reverted the seeding-corpus row" and cited commit `e91e7bf6` — actual: row added by #2697 and still on main; `e91e7bf6` was internal to #2734's branch, unreachable from main. Caught at multi-agent review by `git-history-analyzer`. See `knowledge-base/project/learnings/2026-05-15-deepen-plan-must-grep-cited-attribution-on-main.md`.
- [ ] Every claim about SDK / library / framework runtime semantics ("the SDK rejects X", "the parser refuses Y", "passing flag Z restricts...") cites the exact docstring verbatim — copy the relevant lines from `node_modules/<pkg>/*.d.ts` (or the equivalent type-def file) into the plan and pin the line range. Claims paraphrased from training data or sibling fields routinely shift semantics. **Why:** PR #3338 plan deepen-pass cited `sdk.d.ts:1230` for the load-bearing claim "model literally cannot emit Bash" via `allowedTools` — but `sdk.d.ts:1230` is in the `settings/settingSources` section, and the actual `allowedTools` doc at `sdk.d.ts:858-862` says "auto-allowed without prompting for permission ... To restrict which tools are available, use the `tools` option instead." Three of eight review agents independently caught the misread; a single-author review would have shipped a non-load-bearing fix. See `knowledge-base/project/learnings/2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md` Insight #2.
- [ ] Every GitHub label prescribed in Acceptance Criteria (for tracking issues created post-merge, drain-labeled-backlog targets, or any `gh issue create --label` site) is verified to exist via `gh label list --limit 200 | grep -E "^<label>\b"`. If a label doesn't exist, either substitute the closest existing label (with a note in the AC) or add a Phase 0 step to `gh label create` it. Generalizes the plan SKILL Sharp Edges entry. (Note: the AGENTS.md rule formerly tagged `cq-gh-issue-label-verify-name` was retired 2026-04-23 because `gh` rejects invalid `--label` values with a clear error at create-time; the planning skills still need this AC-time check because the plan ships before any `gh issue create` runs.) **Why:** PR #3378 — plan prescribed `infrastructure` and `seo` labels that didn't exist; substituted with `domain/engineering`, `chore`, `priority/p3-low` at issue-creation time. See `knowledge-base/project/learnings/2026-05-06-plan-prescribed-labels-must-be-verified.md`.
- [ ] Every cited AGENTS.md rule ID (any token matching `\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b` in the plan body, frontmatter, or Research Insights) is verified to **exist as an active rule** via `grep -qE "\[id: <id>\]" AGENTS.md`. Cross-check the retired-rule registry at the repo root (`retired-rule-ids` under the top-level scripts directory) — citing a retired ID as if it were active is a fabrication-class bug (the behavior the rule encoded may still be valid, but the citation is dead). For each fabricated/retired ID: replace with the real load-bearing rule (e.g., the auto-close-keywords rule `wg-use-closes-n-in-pr-body-not-title-to` is the real source for "use `gh issue close` post-apply, not `Closes #N` in PR body") or drop the citation and inline the rationale. **Why:** PR #3486 — the deepen-plan pass on the #3485 runbook cited `cq-when-a-pr-has-post-merge-operator-actions` (fabricated, never existed) and `cq-gh-issue-label-verify-name` (retired) 5x across the plan; both citations were structurally indistinguishable from real ones and only caught by the multi-agent review's `code-quality-analyst` grep. See [llm-authored-plans-cite-fabricated-and-retired-rule-ids.md](../../../../knowledge-base/project/learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md).
- [ ] When the plan creates a **new ADR**, derive its provisional ordinal from a **freshly-fetched `origin/main`** (`git fetch origin main` first), never the branch base: `ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`. ADRs merged after your branch point are invisible to a stale local `main`, so a plan-time pick against the branch base collides with an already-merged ordinal. The number stays provisional (`/ship`'s ADR-Ordinal Collision Gate re-verifies at merge — plan/SKILL.md:534), but deriving from live `origin/main` at plan time avoids handing `/work` a number that was taken before the branch even started. **Why:** PR #6266 — planning subagent picked ADR-103 while ADR-103/104/105 were already merged on origin/main; renumbered 103→106 at review. The exact derivation command already lives in `/work` SKILL.md:634 but no plan-time bullet applied it. See `knowledge-base/project/learnings/2026-07-10-shared-vendor-key-fingerprint-attribution-and-required-iac-secret-apply-gate.md`.
<!-- mirror: plan/SKILL.md loader-class-fit bullet — keep in sync; trim both together -->
- [ ] When a plan proposes any AGENTS.md `core→rest` demotion (`wg-*` only — `hr-*` may not be demoted per CPO sign-off PR #3496 condition 3), verify **loader-class fit**: `grep -n 'DOCS_RE=' -A 25 .claude/hooks/session-rules-loader.sh` to read the `DOCS_RE`/`CODE_RE`/`INFRA_RE` regex block AND the class-selection branch (`docs-only` fires when `HAS_DOCS=1 && HAS_CODE=0 && HAS_INFRA=0` → loads `core+docs-only` only; `code` or `infra` triggers `core+rest`). For each demotion candidate, classify its trigger surface: does it fire on plan/learning/spec edits (docs-only), or only on code/infra? If `docs-only` is in the trigger surface but `AGENTS.rest.md` does NOT load on docs-only, KEEP in core (body-trim instead). Cite the `grep` output + the class-fit determination in the plan body. **Why:** PR #3681 — `wg-plan-prescribed-skills-must-run-inline` was demoted core→rest before pattern-recognition reviewer caught the gap; `/work` runs on docs-only PRs and `AGENTS.rest.md` does not load there. See [agents-md-trim-loader-class-fit-verification.md](../../../../knowledge-base/project/learnings/2026-05-12-agents-md-trim-loader-class-fit-verification.md) (lands with #3681).
- [ ] When a plan prescribes ≥2 workflow constants that must satisfy an equality invariant across distinct step `env:` blocks (poll windows, retry counts, timeout ceilings), reject comment-only cross-links — prescribe a **shared source** (job-level or workflow-level `env:`) AND a **runtime arithmetic assertion** at the first step that uses them. Comments are review-detectable but not load-bearing; the same drift pattern caused #3398. **Why:** PR #3421 — plan deliberately scoped to comment-only coupling for `IN_FLIGHT_CEILING_S` vs `STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S` vs `HEALTH_POLL_MAX_ATTEMPTS * HEALTH_POLL_INTERVAL_S`; architecture-strategist + code-quality-analyst both flagged P2 at review. See `knowledge-base/project/learnings/best-practices/2026-05-07-comment-coupled-workflow-invariants-need-runtime-assertion.md`.
- [ ] When deepen-pass introduces a load-bearing correction (e.g., reduces a `-target=` allow-list count, narrows an AC grep predicate, shifts a bootstrap path from CI to operator-local), **propagate the correction to `knowledge-base/project/specs/feat-<name>/tasks.md` in the same pass** — `tasks.md` is the contract the `work` skill executes against, and stale tasks survive plan-body-only corrections. Also derive AC verification grep expectations from the as-written workflow shape (saved-plan vs inline-apply changes `-target=` placement: saved-plan has `-target=` in plan step only; inline-apply has it in both plan and apply). **Why:** PR #4201 — plan deepen-pass corrected the apply-web-platform-infra.yml allow-list from 3 to 2 -target entries but left tasks.md Phase 4.1 at 3; AC9 grep expected ≥4 matches assuming inline-apply when the workflow uses saved-plan (apply consumes `tfplan` without re-listing -target). Both required mid-implementation reconciliation. See `knowledge-base/project/learnings/2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md` Session Errors §1-2.
- [ ] Every plan-prescribed pathspec→regex translation (`git diff -- '<glob>'` → `grep -E '<re>'` against a cached path-set) verifies equivalence with fixture inputs covering all three shapes: top-level path (no parent dir), single-ancestor path (`<dir>/<target>/<file>`), and deep-nested path (`<dir>/<target>/<sub>/<file>`). Git pathspec `*` crosses `/` (fnmatch with PATHNAME=0); regex `*` does not. The `diff -u <(git diff --name-only -- '<glob>') <(grep -E '<re>' cache)` recipe is necessary but only catches drift when the test repo contains divergent shapes. **Why:** PR #3492 — plan prescribed `/supabase/migrations/[^/]+\.sql$` which under-matched both top-level and nested paths the pathspec `*/supabase/migrations/*.sql` covered; three review agents independently caught it. See `knowledge-base/project/learnings/2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`.
- [ ] When a plan introduces a new routing predicate that reduces the number of review agents (or any downstream gate's coverage) for matching diffs, the plan MUST include an explicit threat-model subsection per class enumerating: (a) what diff shape scores high on the predicate, (b) what malicious payload could ride on that shape, (c) which agent on the full path would catch it, (d) how the predicate excludes that case. Borrow exclusion guards from sibling classes when symmetric (e.g., a `$has_source` empty guard on a deletion-shape class mirroring a lockfile-shape class). **Why:** PR #3492 — `deletion-dominated` initially routed to 2 agents even with new source files; piggyback class caught at multi-agent review. Same learning file as above.
- [ ] When a plan's risk section justifies dropping a positive assertion (or any test coverage) by claiming "the orthogonal test still covers it", verify the cited orthogonal test exercises **the same code path**, not a sibling predicate that happens to share a field name. Field-level overlap is not coverage-level overlap. **Why:** PR #3510 — plan claimed T2's `summary.rules_unused_over_8w` aggregator-side predicate covered T4's dropped positive arm because both touch `fire_count`, but T2 runs in `rule-metrics-aggregate.sh` while T4 runs in `rule-prune.sh` — different scripts, same field. test-design-reviewer caught the gap as P1; fix added T4b with directly-crafted `rule-metrics.json` to bypass the aggregator's `event→first_seen` coupling. See `knowledge-base/project/learnings/2026-05-10-rule-prune-null-first-seen-skip-invalidates-positive-prune-candidate-fixture.md`.
- [ ] When an Acceptance Criterion prescribes a verification grep (`git grep -E '<pattern>' <file>` returns nothing/N) against a file that contains **multiple top-level targets** (a workflow with N jobs, a config with N stanzas, a schema with N tables, a router with N routes), AND the plan's Out-of-Scope section excludes any of those targets, the AC's grep MUST be section-scoped to the target under change (e.g., `awk '/^  <target-key>:/,0' <file> | grep ...`). Whole-file grep silently fails when the excluded target legitimately retains the matched pattern — the AC's intent contradicts itself by construction. **Why:** PR #3654 — plan AC #4.3 prescribed `git grep -E 'ms-playwright|playwright-cache|install-deps chromium' .github/workflows/{ci,deploy-docs}.yml` returns nothing, but the `e2e` job in `ci.yml` (explicitly out of scope per the same plan) still uses all three patterns. See `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md` Session Errors §2.
- [ ] When a plan migrates a CI job to a vendor-supplied container image (`mcr.microsoft.com/playwright:*`, `cypress/included:*`, language-specific images, etc.), enumerate every existing step's `uses:` action AND every `run:` shell-out dependency, then `docker run <image> which <tool>` each one empirically. Vendor base images are scoped to their primary tool (Playwright Jammy = Node + Chromium; Cypress = Node + Cypress browsers); generic CLI tooling (`unzip`, `git`, `jq`, `make`, `gcc`, `tar`, `gzip`, `xz-utils`) may be absent. Failure mode is the action failing fast at setup — e.g., `oven-sh/setup-bun` shelling out to `unzip` and emitting `error: unzip is required to install bun` (open issue oven-sh/setup-bun#55). Plan-time mitigation: add a one-line `apt-get update -qq && apt-get install -y -qq --no-install-recommends <pkgs>` step BEFORE the dependent action, AND document why in the workflow comment. **Why:** PR #3664 — `setup-bun` inside `mcr.microsoft.com/playwright:v1.58.2-jammy` failed because unzip is absent; deepen-plan caught it empirically pre-push. See `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md` "Follow-up: when the consumer uses bun instead of npm".
- [ ] When a plan binds an Acceptance Criterion to a specific shell primitive whose behavior depends on **process-group / session / signal-defer semantics** (`kill 0` / `kill -- -$$` / `set -m` / `setsid` / signal traps + foreground commands), write a 10-line `parent.sh`/`child.sh` repro and run it before committing the AC to text. Man-page and "verified in tooling" lookups frequently miss the runtime context that matters: e.g., `set -m` puts CHILDREN in new PGIDs but does NOT move bash itself out of its parent's PGID, so `kill -TERM 0` from a fork-exec'd child reaches the parent. Plan v1 of #3704 prescribed `kill -TERM 0` on this incorrect assumption; the repro at /work confirmed the bug pre-merge. Same class for `wait` vs foreground-defer: bash dispatches TERM traps only between commands or in `wait $!`, never during a hung `docker pull`. **Why:** PR #3704 — see `knowledge-base/project/learnings/2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`.
- [ ] When a plan verifies a multi-clause SQL predicate (`IF A AND B THEN ... flag := true; END IF`, `CASE WHEN A AND B`, `OR ... AND ...` n-ary, idempotent-update guards) by citing line numbers, the plan body MUST literally restate EVERY operand of the predicate alongside the line citation — never paraphrase a predicate by its most-discussed clause alone. A predicate of shape `IF v_paused_at IS NULL AND v_total > v_cap THEN v_flag := true` requires restating both `v_paused_at IS NULL` (when true, when false, when it flips) AND `v_total > v_cap` AND the conjunction (`v_flag` true iff BOTH clauses fire, not either alone). Same rule for migration triggers, plpgsql functions, and any boolean predicate with ≥2 operands. **Why:** PR #3987 — deepen-pass on migration `046_runtime_cost_state.sql:227` extracted `v_total > v_cap` but missed the `v_paused_at IS NULL` co-condition; plan documented "calls 6-10 return kill_tripped=true" while the actual invariant (stronger atomicity: exactly one call wins the flip) was discovered only at /work time when live-DB test failed. Same defect class as `2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md` (TS union enumeration) extended to SQL boolean predicates. See `knowledge-base/project/learnings/2026-05-18-premise-validation-and-multi-clause-predicate-reading.md`.
- [ ] When a plan models an AGENTS always-loaded byte reduction (`B_ALWAYS` under `lint-agents-rule-budget.py`), size the achievable trim from **rationale bytes only** (multi-clause `**Why:**` narrative, `see …/<file>.md` path tails, restated examples) — NOT from imperative/directive prose, which is effectively incompressible without weakening guidance. A lever framed as "tighten N% of imperative prose" will overshoot. Carry "raise the advisory ceiling (issue path-b) + wire the gate at the realistic floor" as an explicit pre-approved fallback rather than assuming `< target` is always reachable; demoting `wg-*` gates only helps for ship/merge-phase gates that never fire on single-class docs-only sessions (#3681) AND are not pinned to core by a component test — `grep -rl '<gate-id>' plugins/soleur/test/` and read hits for `→ core`/cross-ref assertions before planning a demotion; a clean `lint-rule-ids.py` is necessary but NOT sufficient (it pins only `hr-*`/`[compliance-tier]`). **Why:** PR #4599 — modelled core ≈15741 via −2100 B "imperative tightening" that didn't exist; landed 22915 and raised reject 22000→23000. Demoting `wg-block-pr-ready-on-undeferred-operator-steps` broke `ship-undeferred-operator-step-gate.test.ts` in CI post-merge-queue. See `knowledge-base/project/learnings/2026-05-29-agents-byte-budget-trim-from-rationale-not-directive.md`.
- [ ] Every grep-based Acceptance Criterion whose scope contains the plan or its paired `tasks.md` includes `--exclude-dir=<spec-dir>` and `--exclude=<plan-basename>.md` flags. Plans that quote the search pattern in prose ("rename `X` to `Y`", "no remaining `X` references") cause whole-scope greps to match the plan itself post-edit. AND: every backticked identifier the plan cites with a file:line attribution (Terraform variable, function, schema column, env-var, RPC name) is re-read from the declaration line — not copied from the issue body — and the plan quotes the declaration form (e.g., `variable "app_domain" { ... }`), not the default value alone. Treat upstream identifiers (issue prose, sibling PR text) as hypotheses, not facts. **Why:** PR #4160 — plan AC1 claimed `grep -rE 'web-platform.soleur.ai' knowledge-base/` returns 0 lines but the plan + tasks.md retained the literal string in prose; same plan cited the Terraform variable as `app_subdomain` 4x (actual: `app_domain` at `variables.tf:85-89`). Both caught at work + review. See `knowledge-base/project/learnings/best-practices/2026-05-20-plan-acs-self-grep-scope-and-identifier-source-verification.md`.
- [ ] Enhancement summary accurately reflects changes

## Post-Enhancement Options

After writing the enhanced plan, use the **AskUserQuestion tool** to present these options:

**Question:** "Plan deepened at `[plan_path]`. What would you like to do next?"

**Options:**

1. **View diff** - Show what was added/changed
2. **Run `/plan_review`** - Get feedback from reviewers on enhanced plan
3. **Start `soleur:work`** - Begin implementing this enhanced plan
4. **Deepen further** - Run another round of research on specific sections
5. **Revert** - Restore original plan (if backup exists)

Based on selection:

- **View diff** -> Run `git diff [plan_path]` or show before/after
- **`/plan_review`** -> Call the /plan_review command with the plan file path
- **`soleur:work`** -> Use `skill: soleur:work` with the plan file path
- **Deepen further** -> Ask which sections need more research, then re-run those agents
- **Revert** -> Restore from git or backup

## Example Enhancement

**Before (from `soleur:plan`):**

```markdown
## Technical Approach

Use React Query for data fetching with optimistic updates.
```

**After (from /deepen-plan):**

```markdown
## Technical Approach

Use React Query for data fetching with optimistic updates.

### Research Insights

**Best Practices:**
- Configure `staleTime` and `cacheTime` based on data freshness requirements
- Use `queryKey` factories for consistent cache invalidation
- Implement error boundaries around query-dependent components

**Performance Considerations:**
- Enable `refetchOnWindowFocus: false` for stable data to reduce unnecessary requests
- Use `select` option to transform and memoize data at query level
- Consider `placeholderData` for instant perceived loading

**Implementation Details:**
```typescript
// Recommended query configuration
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      retry: 2,
      refetchOnWindowFocus: false,
    },
  },
});
```

**Edge Cases:**

- Handle race conditions with `cancelQueries` on component unmount
- Implement retry logic for transient network failures
- Consider offline support with `persistQueryClient`

**References:**

- <https://tanstack.com/query/latest/docs/react/guides/optimistic-updates>
- <https://tkdodo.eu/blog/practical-react-query>

```
