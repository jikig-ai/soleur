---
title: "feat: Target-User-Impact Workflow Gate"
date: 2026-04-24
feature: feat-user-impact-gate
branch: feat-user-impact-gate
worktree: .worktrees/feat-user-impact-gate/
issue: 2888
triggered_by: 2887
pr: 2889
brainstorm: knowledge-base/project/brainstorms/2026-04-24-target-user-impact-gate-brainstorm.md
spec: knowledge-base/project/specs/feat-user-impact-gate/spec.md
detail_level: A-LOT
status: planned
owner: CPO
---

# feat: Target-User-Impact Workflow Gate

## Overview

Thread a new workflow gate through five Soleur skills (`brainstorm` → `plan` → `deepen-plan` → `review` → `preflight`) and one AGENTS.md hard rule. Every design/plan/PR that touches credentials, auth, data persistence, payments, or user-owned resources MUST answer **"what is the worst thing the target user experiences if this fails — silently or loudly?"** before implementation begins.

Triggered by incident #2887: the `dev` and `prd` Doppler configs for the `soleur` project both hold connection strings pointing at the same Supabase project. A single-user data-breach shape shipped for months because every existing gate weighed the decision on technical and convenience axes only — no gate asked what a user breach would cost the brand.

## User-Brand Impact

*(Dogfooding the section this plan itself introduces — demonstrating the pattern we're codifying.)*

- **If this lands broken, the user experiences:** nothing observable directly. The gate protects users indirectly — a broken gate means the next #2887-class bug silently ships. Worst case: a future feature that should have been caught (e.g., a third Doppler collapse, a cross-tenant read, a billing race) ships without its framing question answered, and a real user's data / workflow / money is exposed.
- **If this leaks, the user's data/workflow/money is exposed via:** second-order failure of subsequent PRs that would otherwise have been gated. The gate's own code surface is workflow/markdown — no direct data path.
- **Brand-survival threshold:** `single-user incident`. The gate exists precisely to catch single-user-breach-class bugs; shipping it incorrectly (false-negative gate that passes when it should halt) reintroduces the exact class #2887 exemplifies.
- **Required sign-off:** CPO + user-impact-reviewer before `/work`. This plan meets that bar — CPO assessed in brainstorm Phase 0.5; user-impact-reviewer will be invoked at review-time per the conditional-agent entry this plan introduces.

## Research Reconciliation — Spec vs. Codebase

All claims in the spec have been verified against the codebase:

| Spec claim | Reality (verified in this plan phase) | Plan response |
|---|---|---|
| AGENTS.md ~36,878 bytes; 1 byte under 37k warn | Confirmed: `wc -c AGENTS.md` → 36878 | Accept 37.3k post-merge; drafting rule ≤570 bytes leaves ≤37.5k |
| Preflight has Checks 1-3 (migration, security, lockfile) | Confirmed via read: Phase 1 runs 4 parallel items (Not-Bare-Repo + Checks 1-3) | Add Check 4 "Brand-Survival Self-Review" in same Phase 1 parallel set |
| deepen-plan Phase 4.5 is the firewall-halt template | Confirmed: Phase 4.5 "Network-Outage Deep-Dive" — conditional content-grep enforcement with rule-application telemetry | Add Phase 4.6 "User-Brand Impact Halt" mirroring same structure |
| `<conditional_agents>` block in review SKILL.md at lines 102-176 | Confirmed: agents numbered 9-14 (Rails 9-10, migration 11-12, test-design 13, semgrep 14) | New user-impact-reviewer = agent #15; insert before line 176 `</conditional_agents>` close |
| security-sentinel.md is an existing review agent template | Confirmed: `plugins/soleur/agents/engineering/review/security-sentinel.md` exists; format is `name + description + model: inherit + body` | Use as template for new `user-impact-reviewer.md` |
| 15 review agents exist | Confirmed via `ls`: 15 .md files in `plugins/soleur/agents/engineering/review/` | New agent brings count to 16 |
| Domain-config.md uses pipe-delimited table; CPO/CLO/CTO are existing rows | Confirmed | No new row; add `user-brand-critical` tag-handling note to the table's processing instructions |
| No "user-brand" vocabulary in codebase | Confirmed: zero hits for `user-brand` / `brand-survival` / `single-user incident` | Plan introduces canonical vocabulary |
| Functional discovery confirms novelty | 3 registries checked (api.claude-plugins.dev, claudepluginhub.com, anthropics marketplace) — zero functional match | Proceed with in-house implementation |

No blocking discrepancies found.

## Open Code-Review Overlap

**None.** Queried all 200 open `code-review` labeled issues against the 8 planned file paths (brainstorm SKILL.md, domain-config.md, plan SKILL.md, deepen-plan SKILL.md, review SKILL.md, preflight SKILL.md, AGENTS.md, user-impact-reviewer.md). Zero overlap — nothing to fold in, acknowledge, or defer.

## Files to Edit

1. **`plugins/soleur/skills/brainstorm/SKILL.md`** — Insert new Phase 0.1 "User-Impact Framing" before Phase 0.25 Roadmap Freshness Check. Add `AskUserQuestion` presentation of the user-impact question, trigger-keyword parsing, and `user-brand-critical` tag assignment.
2. **`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`** — Add a `## User-Brand-Critical Tag Processing` section below the table explaining that when the brainstorm Phase 0.1 tag fires, CPO + CLO + CTO spawn in parallel **before** any other specialists, regardless of standard domain assessment results.
3. **`plugins/soleur/skills/plan/SKILL.md`** — Add mandatory `## User-Brand Impact` section to all plan templates (in `plan-issue-templates.md` MINIMAL/MORE/A-LOT). Add Phase 2.6 "User-Brand Impact Section Check" after Phase 2.5 Domain Review Gate. Document CPO + user-impact-reviewer sign-off gate for `single-user incident` threshold.
4. **`plugins/soleur/skills/plan/references/plan-issue-templates.md`** — Add `## User-Brand Impact` template block to all three detail tiers.
5. **`plugins/soleur/skills/deepen-plan/SKILL.md`** — Add new Phase 4.6 "User-Brand Impact Halt" mirroring Phase 4.5 structure. Grep the plan for `^## User-Brand Impact`; if absent, exit with error pointing at `plan-issue-templates.md`. Emit rule-application telemetry.
6. **`plugins/soleur/skills/review/SKILL.md`** — Inside `<conditional_agents>` block (line 102-176), add a new section for agent #15 `user-impact-reviewer`. Trigger: plan body contains `Brand-survival threshold: single-user incident`. Include "When to run" (threshold match) and "What this agent checks" (specific user-facing artifact + specific exposure vector; reject generic boilerplate).
7. **`plugins/soleur/skills/preflight/SKILL.md`** — Add new Check 4 "Brand-Survival Self-Review" to Phase 1 parallel set. Structure: Step 4.1 detect sensitive-path diff (broader globs), Step 4.2 check PR body for `## User-Brand Impact`, Step 4.3 validate threshold + scope-out override (`threshold: none, reason: <text>`), Step 4.4 PASS/FAIL/SKIP report. Headless mode: abort on FAIL; interactive: prompt to fill section.
8. **`AGENTS.md`** — Append new Hard Rule under 600 bytes. Proposed ID: `hr-weigh-every-decision-against-target-user-impact`. Points at #2888 + #2887.

## Files to Create

1. **`plugins/soleur/agents/engineering/review/user-impact-reviewer.md`** — New agent definition following the `security-sentinel` template (YAML frontmatter + body). Single-job prompt contract: enumerate every way the change can hurt a user, require each explicitly mitigated or scope-outed. Reject generic boilerplate. Must include `model: inherit` per the plugin agent compliance checklist.
2. **`knowledge-base/project/specs/feat-user-impact-gate/smoke-evidence.md`** — Evidence artifact from in-session smoke run. Contains: synthetic plan path (created then deleted), command outputs from `/soleur:plan`, `/soleur:review`, `/soleur:ship`/`preflight`, confirmation that each gate fired.

## Implementation Phases

*Ordered to unblock the end-to-end smoke scenario as late as possible while keeping incremental commits reviewable.*

### Phase A — Foundations (independent, parallelizable)

**Goal:** Establish the vocabulary (AGENTS.md rule) and the reviewer agent file. Both have zero downstream dependencies and can go first.

- **Task A1:** Draft AGENTS.md Hard Rule.
  - Draft text (~560 bytes target; final verified ≤600 at commit time):
    ```
    - Every design/plan/PR touching credentials, auth, data persistence, payments, or user-owned resources MUST answer "what is the worst thing the target user experiences if this fails, silently or loudly?" before `/work` [id: hr-weigh-every-decision-against-target-user-impact] [skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review conditional agent, preflight Check 4]. Threshold `single-user incident` requires CPO + user-impact-reviewer sign-off. **Why:** #2887 — dev/prd Supabase collapse shipped for months; no gate asked what one user's breach would cost the brand. See #2888.
    ```
  - Insert after the last Hard Rule (`hr-never-fake-git-author`) but before `## Workflow Gates`.
  - **Verification:** `awk '/hr-weigh-every-decision/ { n=1 } n { print; n=0 }' AGENTS.md | wc -c` must be ≤600 (excluding leading `- `). Run `python3 scripts/lint-rule-ids.py` — must pass.
  - **Byte check:** `wc -c AGENTS.md` post-insert must be <40000 (critical threshold) and will cross 37000 (warn) — accept per brainstorm decision #8.

- **Task A2:** Create `plugins/soleur/agents/engineering/review/user-impact-reviewer.md`.
  - YAML frontmatter:
    ```yaml
    ---
    name: user-impact-reviewer
    description: "Use this agent when a plan marks brand-survival threshold as single-user incident. Reviews the diff against the plan's `## User-Brand Impact` section to verify every way the change could hurt a user is explicitly mitigated or scope-outed. Rejects generic boilerplate. Use security-sentinel for OWASP/vulnerability scanning; use this agent for user-impact enumeration against the declared threshold."
    model: inherit
    ---
    ```
  - Body sections: Core Review Protocol, Prompt Contract, Rejection Criteria, Output Format.
  - **Prompt contract (required):** output MUST name (a) a specific user-facing artifact (email, workspace, API key, conversation, message, billing event) and (b) a specific exposure vector (cross-tenant read, credential leak, data loss, double-charge, silent drop).
  - **Rejection criteria:** reject if the `## User-Brand Impact` section contains ONLY generic strings (`"users experience a bug"`, `"error state"`, `"generic failure"`, empty bullets, `TBD`, `TODO`).
  - **Verification:** run `bun test plugins/soleur/test/components.test.ts` (per plugin AGENTS.md) to confirm agent descriptions + skill descriptions stay within word budget. New agent adds ~55 words to the cumulative 2500-word agent description cap.
  - Token-budget check also via `grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` — expected result under 2500.

### Phase B — Plan section (mandatory template change)

**Goal:** Every plan output henceforth contains the `## User-Brand Impact` section. This unblocks Phase C (deepen-plan halt must grep for it).

- **Task B1:** Edit `plugins/soleur/skills/plan/references/plan-issue-templates.md`.
  - Add the following section to MINIMAL, MORE, and A-LOT templates (below the Goals/Non-Goals block):
    ```markdown
    ## User-Brand Impact

    - **If this lands broken, the user experiences:** [concrete, named user-facing artifact]
    - **If this leaks, the user's [data / workflow / money] is exposed via:** [concrete exposure vector]
    - **Brand-survival threshold:** `none` | `single-user incident` | `aggregate pattern`

    *Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: <one sentence naming why the touched path is not user-impacting>`
    ```

- **Task B2:** Edit `plugins/soleur/skills/plan/SKILL.md` to add Phase 2.6 "User-Brand Impact Section" after Phase 2.5 Domain Review Gate. The phase instructs the plan skill to:
  1. Ensure the plan draft contains the `## User-Brand Impact` section with all three lines filled in (not TBD).
  2. If threshold = `single-user incident`, mark the plan with a YAML frontmatter line `requires_cpo_signoff: true` and display: "CPO sign-off required before `/work`. Invoke CPO domain leader or confirm CPO has reviewed the brainstorm."
  3. Add a "Sharp Edges" entry noting that a plan with an empty or TBD section will fail deepen-plan (Phase 4.6).
  - Carry-forward rule: when a brainstorm document exists with its own `## User-Brand Impact` framing (which this plan demonstrates), plan Phase 2.6 may import the threshold and user-facing-artifact declarations directly rather than re-authoring.

### Phase C — deepen-plan halt (hard gate)

**Goal:** Enforce Phase B's template at the deepen-plan entry point.

- **Task C1:** Edit `plugins/soleur/skills/deepen-plan/SKILL.md`. Add new Phase 4.6 immediately after Phase 4.5 (Network-Outage Deep-Dive):

  ```markdown
  ### 4.6. User-Brand Impact Halt (Always)

  Grep the target plan for the `## User-Brand Impact` heading:

  ```bash
  grep -q '^## User-Brand Impact' <plan-file>
  ```

  If the heading is absent, OR the section is empty, OR every bullet contains only `TBD` / `TODO` / generic placeholder text, HALT with:

  > Error: Plan is missing `## User-Brand Impact` section (or contains only placeholders).
  > See `plugins/soleur/skills/plan/references/plan-issue-templates.md` for the template.
  > Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, every plan
  > must answer the user-impact framing question before deepen-plan can proceed.

  On halt, emit rule-application telemetry:

  ```bash
  source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
    emit_incident hr-weigh-every-decision-against-target-user-impact applied \
    "Every design/plan/PR touching credentials, auth, data p"
  ```
  ```

  - **Verification:** run deepen-plan against a deliberately-missing-section synthetic plan; confirm halt message is surfaced and rule-metrics JSONL contains the telemetry entry.

### Phase D — Review conditional agent

**Goal:** Wire user-impact-reviewer into the multi-agent review flow.

- **Task D1:** Edit `plugins/soleur/skills/review/SKILL.md` inside the `<conditional_agents>` XML block. Insert this new section after the test-design-reviewer block (line 146-161) and before the semgrep-sast block (line 163):

  ```markdown
  **If the plan body marks Brand-survival threshold as `single-user incident`:**

  15. Task user-impact-reviewer(PR content + plan path) - Enumerate every user-facing failure mode implied by the diff and verify the plan's `## User-Brand Impact` section mitigates or scope-outs each

  **When to run user-impact-reviewer:**

  - The plan file in `knowledge-base/project/plans/<plan>.md` contains literal text `Brand-survival threshold: single-user incident`
  - The PR body contains `## User-Brand Impact` with that threshold label

  **What this agent checks:**

  - `user-impact-reviewer`: Enumerates concrete user-facing artifacts exposed by the change (email, workspace, API key, conversation, message, billing event) AND a concrete exposure vector per artifact (cross-tenant read, credential leak, data loss, double-charge, silent drop). Rejects generic boilerplate as a finding ("users experience a bug"). Co-exists with security-sentinel — security-sentinel handles OWASP/CWE scanning, user-impact-reviewer handles user-facing-outcome enumeration against the plan's declared threshold.
  ```

  - Renumber downstream agent (semgrep-sast stays at its semantic position but its numeric label becomes #16).
  - **Verification:** re-read the review SKILL.md after edit, confirm XML tag structure unbroken, confirm numbering contiguous 1-16.

### Phase E — Preflight Check 4 (ship-time gate)

**Goal:** Fail `/soleur:ship` when sensitive paths are touched without an answered User-Brand Impact section.

- **Task E1:** Edit `plugins/soleur/skills/preflight/SKILL.md` Phase 1. Add Check 4 after Check 3 (Lockfile Consistency):

  ```markdown
  ### Check 4: Brand-Survival Self-Review

  **Step 4.1: Detect sensitive-path diff.**

  ```bash
  git diff --name-only origin/main...HEAD
  ```

  Check if any changed files match these globs (broader-glob strategy per brainstorm decision #7):

  - `apps/web-platform/server/**`
  - `apps/web-platform/supabase/**`
  - `apps/web-platform/lib/stripe*`, `apps/web-platform/lib/auth*`, `apps/web-platform/lib/byok*`
  - `infra/**`
  - `**/doppler*.{yml,yaml,sh}`
  - `.github/workflows/*doppler*.yml`

  If no sensitive paths touched, return **SKIP**.

  **Step 4.2: Fetch PR body.**

  Two separate Bash calls (no command substitution per Phase 0 rule):

  ```bash
  gh pr view --json body --jq .body > /tmp/pr-body.md
  ```

  If no PR exists (running in a branch without a draft PR), return **SKIP** with note: "No PR body available — cannot validate section."

  **Step 4.3: Check for `## User-Brand Impact` section.**

  ```bash
  grep -q '^## User-Brand Impact' /tmp/pr-body.md
  ```

  If absent, return **FAIL** with: "Sensitive-path diff detected but PR body is missing `## User-Brand Impact` section. Add the section per `plan-issue-templates.md`."

  **Step 4.4: Validate threshold + scope-out.**

  Extract the threshold line:

  ```bash
  grep -E '^.*Brand-survival threshold:' /tmp/pr-body.md
  ```

  - If threshold is `single-user incident` or `aggregate pattern`: **PASS**.
  - If threshold is `none`: check for inline scope-out note matching `threshold: none, reason: <text>` within the section body.
    - Scope-out present: **PASS**.
    - Scope-out absent: **FAIL** with: "Sensitive-path diff with `threshold: none` requires a `threshold: none, reason: <why>` scope-out note in the User-Brand Impact section."

  **Headless mode behaviour:** On **FAIL**, abort with error details (no prompt). On **PASS/SKIP**, continue silently.

  **Interactive mode behaviour:** On **FAIL**, present the section requirement and offer `AskUserQuestion` with options: (a) "Fill in section now" (prompt the user for the three lines, write to PR body via `gh pr edit --body-file -`), (b) "Add scope-out note" (if threshold defensibly `none`), (c) "Abort — fix elsewhere".

  **Result:**

  - **PASS** — No sensitive paths touched, OR section present with valid threshold, OR valid scope-out for `none` threshold
  - **FAIL** — Sensitive-path diff + missing/empty section, OR `threshold: none` without scope-out note
  - **SKIP** — No PR exists to check body, OR no sensitive paths touched
  ```

  - Update Phase 2 Aggregate Report table to include Check 4.
  - **Verification:** run preflight against the smoke scenario's synthetic plan PR; confirm FAIL fires with expected message.

### Phase F — Brainstorm Phase 0.1 (framing-time gate)

**Goal:** Force the user-impact framing at the earliest decision point. This phase comes last among the skill edits because the smoke scenario (Phase G) does not exercise brainstorm — and the gate's enforcement layer (Phase E preflight) is what catches regressions.

- **Task F1:** Edit `plugins/soleur/skills/brainstorm/SKILL.md`. Insert a new `### Phase 0.1: User-Impact Framing` between the existing Phase 0 (Setup) end and Phase 0.25 (Roadmap Freshness Check).

  Phase content:
  1. Use `AskUserQuestion` tool to present:
     > **Question:** "If this decision ships as designed, what is the worst outcome the target user experiences? If it silently fails, what do they see? If it leaks, what data of theirs is exposed? (Answer even if the request seems purely technical — the framing is the point.)"
     > **Header:** "User impact"
     > **Options:** Free-text (use `other` escape) — this is not a selection question.
  2. Parse the answer for trigger keywords (case-insensitive substring match):
     `data loss` | `trust breach` | `credential exposure` | `billing surprise` | `user data` | `credentials` | `payment` | `auth` | `session` | `pii` | `private`
  3. If any keyword matches, set `USER_BRAND_CRITICAL=true` for the session and announce: "Tagged as user-brand-critical. CPO + CLO + CTO will be spawned in parallel at Phase 0.5 before other specialists."
  4. If no keyword matches, set `USER_BRAND_CRITICAL=false` and proceed silently.
  5. Emit rule-application telemetry on match:
     ```bash
     source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
       emit_incident hr-weigh-every-decision-against-target-user-impact applied \
       "Every design/plan/PR touching credentials, auth, data p"
     ```

- **Task F2:** Edit `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Add below the table:

  ```markdown
  ## User-Brand-Critical Tag Processing

  When Phase 0.1 sets `USER_BRAND_CRITICAL=true`, override the standard domain-sweep ordering: spawn **CPO + CLO + CTO** in parallel FIRST (before any other relevant domain leader determined by Assessment Questions above). Other domain leaders still run in parallel where relevant, but CPO/CLO/CTO are mandatory for user-brand-critical sessions regardless of Assessment Question matches.

  Rationale: user-brand-critical decisions need product (CPO), legal/compliance (CLO), and architectural blast-radius (CTO) framing before any domain-specific deep-dives. Security-sentinel remains a review-time agent only — it is not a brainstorm domain leader.
  ```

  - Phase 0.5 Processing Instructions are updated to check `USER_BRAND_CRITICAL` before standard assessment and conditionally expand the domain set.

### Phase G — End-to-end smoke scenario

**Goal:** Validate the full gate stack against a realistic user-impacting diff before shipping.

- **Task G1:** Author a synthetic plan at `knowledge-base/project/plans/_smoke-synthetic-user-impact-gate-plan.md` (underscore prefix to mark it as non-canonical):
  - Overview says it adds session-token validation to `apps/web-platform/server/session-sync.ts`.
  - DELIBERATELY omits the `## User-Brand Impact` section.

- **Task G2:** Run gates in order:
  1. `deepen-plan _smoke-synthetic-user-impact-gate-plan.md` — MUST halt with Phase 4.6 error. Capture stdout.
  2. Fill the section in with threshold `single-user incident` + concrete artifact/vector. Re-run deepen-plan — MUST pass.
  3. Open a branch and push a dummy edit to `apps/web-platform/server/session-sync.ts` (add a one-line comment, to touch the sensitive path). Do NOT add the section to the PR body yet.
  4. Create draft PR. Run `/soleur:preflight` Check 4 — MUST FAIL with missing-section message.
  5. Add the section to the PR body via `gh pr edit`. Re-run preflight — MUST PASS.
  6. Run `/soleur:review` — MUST spawn `user-impact-reviewer` (confirm its Task invocation appears in the transcript).

- **Task G3:** Write `knowledge-base/project/specs/feat-user-impact-gate/smoke-evidence.md` containing:
  - Timestamp, command used for each step, captured stdout/stderr.
  - Screenshots NOT required (skill-markdown change only, no UI).
  - Confirmation that each of the 4 gate layers (deepen-plan halt, preflight Check 4, review conditional agent, AGENTS.md rule visibility) fired as designed.

- **Task G4:** Clean up — delete `_smoke-synthetic-user-impact-gate-plan.md` from the worktree, revert the dummy edit to session-sync.ts, close the smoke draft PR if one was opened. Keep the smoke-evidence.md artifact.

### Phase H — Ship

- **Task H1:** Add `## Changelog` section to PR #2889 body per plugin AGENTS.md. Change class is `semver:minor` (new skill behaviors + new review agent).
- **Task H2:** Run `/soleur:ship` per standard flow. Expected: preflight Check 4 PASSES (the plan's PR itself declares `threshold: single-user incident` via this document).
- **Task H3:** Post-merge: verify AGENTS.md loaded correctly into next session (byte count, rule visible in context).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm Phase 0.5)

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Markdown prompts are advisory; CI workflow would be the load-bearing enforcement layer but is deferred to #2890. Broader glob strategy survives codebase growth. AGENTS.md byte budget tight but viable at 37.3k. Smoke scenario runnable in-session ~30 min. Review-time generic-boilerplate risk mitigated by user-impact-reviewer's prompt contract (specific artifact + vector required).

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Full-scope shape accepted over narrower MVP. Checkbox risk remains; user-impact-reviewer prompt contract is the primary mitigation. CPO sign-off on `single-user incident` threshold could become a bottleneck — 6-month metric: distribution of threshold labels (healthy signal ≥20% `single-user incident` on sensitive-path PRs; red flag 100% `none`).

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Net-new touchpoint — CLO was not previously in pre-implementation gates for credential/DB/user-data decisions. Clear fit for the #2887 incident class (data-isolation failure has direct legal implications). No new legal documents required by this PR; legal lens is applied at framing-time only.

### Product/UX Gate

**Tier:** NONE — this plan discusses UI concepts but implements workflow orchestration changes only. Per plan SKILL.md guidance: "A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE." No new files match `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

**Agents invoked:** none (NONE tier)
**Skipped specialists:** none
**Pencil available:** N/A

**Brainstorm-recommended specialists:** none outside the UX-Gate pipeline; brainstorm Domain Assessments did not recommend conversion-optimizer, retention-strategist, or pricing-strategist.

## Acceptance Criteria

### Pre-merge (PR #2889)

- [ ] **AC1 — AGENTS.md rule landed.** `grep -q 'hr-weigh-every-decision-against-target-user-impact' AGENTS.md` returns 0. `python3 scripts/lint-rule-ids.py` passes. `wc -c AGENTS.md` result < 40000.
- [ ] **AC2 — New agent file landed.** `plugins/soleur/agents/engineering/review/user-impact-reviewer.md` exists; `bun test plugins/soleur/test/components.test.ts` passes; agent description total word-count under 2500.
- [ ] **AC3 — Plan template updated.** `plan-issue-templates.md` has `## User-Brand Impact` in MINIMAL, MORE, A-LOT blocks.
- [ ] **AC4 — deepen-plan Phase 4.6 halt works.** Smoke scenario demonstrates halt (captured in `smoke-evidence.md`).
- [ ] **AC5 — Review conditional agent wired.** Grep for `user-impact-reviewer` in `review/SKILL.md` returns a line inside the `<conditional_agents>` block; numbering contiguous 1-16.
- [ ] **AC6 — Preflight Check 4 wired.** Grep for `Brand-Survival Self-Review` in `preflight/SKILL.md` returns the new section; Phase 2 table updated.
- [ ] **AC7 — Brainstorm Phase 0.1 inserted.** Phase 0.1 heading exists and references the `AskUserQuestion` step + trigger-keyword list.
- [ ] **AC8 — Domain-config note added.** `brainstorm-domain-config.md` contains `## User-Brand-Critical Tag Processing` section documenting CPO+CLO+CTO escalation.
- [ ] **AC9 — Smoke evidence captured.** `knowledge-base/project/specs/feat-user-impact-gate/smoke-evidence.md` exists; lists 4 gate-fire confirmations with command outputs.
- [ ] **AC10 — Synthetic plan removed.** `_smoke-synthetic-user-impact-gate-plan.md` does NOT exist in the worktree at merge time.
- [ ] **AC11 — This PR's own User-Brand Impact section is present.** PR #2889 body has `## User-Brand Impact` with `Brand-survival threshold: single-user incident` (the dogfood requirement — the PR that adds the gate must pass the gate).
- [ ] **AC12 — `## Changelog` with `semver:minor` label applied to PR.**
- [ ] **AC13 — Review passes.** DHH, Kieran, simplicity, and user-impact-reviewer (bootstrap-invoked on itself) all return either CONCUR or actionable inline fixes.

### Post-merge (operator)

- [ ] **AC14 — Next session verifies AGENTS.md load.** After merge, start a fresh session on main; confirm the new hard rule appears in the loaded AGENTS.md context. No action required if load is clean.
- [ ] **AC15 — Deferral issues remain open.** `#2890` (CI workflow), `#2891` (AGENTS.md retirement audit), `#2892` (threshold taxonomy review) stay open per brainstorm decision #9 and non-goals.
- [ ] **AC16 — One-week re-read.** Seven days post-merge, re-run the smoke scenario against current main to confirm no skill-edit regression.

## Test Scenarios

Each corresponds to a Phase G step:

1. **T1 — deepen-plan halt on missing section.** Synthetic plan without section → deepen-plan exits with referenced error. Expected stderr: `Error: Plan is missing \`## User-Brand Impact\` section`.
2. **T2 — deepen-plan pass on filled section.** Synthetic plan with `threshold: single-user incident` + concrete artifact/vector → deepen-plan completes normally.
3. **T3 — preflight Check 4 FAIL.** Branch with dummy edit to `apps/web-platform/server/session-sync.ts` + PR body missing section → Check 4 returns FAIL.
4. **T4 — preflight Check 4 PASS after fill.** Same branch with section added to PR body via `gh pr edit` → Check 4 returns PASS.
5. **T5 — preflight Check 4 PASS on scope-out.** Branch with dummy edit + PR body declares `threshold: none, reason: <one sentence>` → Check 4 returns PASS (scope-out accepted).
6. **T6 — review spawns user-impact-reviewer.** PR with `Brand-survival threshold: single-user incident` in body → `/soleur:review` invokes the new agent as a Task (verify in transcript).
7. **T7 — Review does NOT spawn for threshold=none.** PR with `threshold: none, reason: ...` → review spawns standard 8 agents + 3 conditional agents; `user-impact-reviewer` NOT invoked.
8. **T8 — AGENTS.md rule visible next session.** Open a fresh `claude-code` session on a branch with this PR merged → AGENTS.md context includes the new hr-* line.
9. **T9 — Telemetry emission.** After deepen-plan halt AND brainstorm Phase 0.1 tag-match, `.claude/.rule-incidents.jsonl` contains entries keyed by `hr-weigh-every-decision-against-target-user-impact applied`.

## Non-Goals (explicit)

- **CI workflow enforcement** — deferred to #2890. Known gap: humans merging via GitHub UI bypass preflight.
- **Retiring `cq-doppler-service-tokens-are-per-config`** — complementary rule, stays.
- **Adding `security-sentinel` as a brainstorm domain leader** — review-only agent; Phase 0.1 escalation set is CPO + CLO + CTO only.
- **Automated generic-boilerplate grep-detector** in preflight — the `user-impact-reviewer` handles this at review time via prompt contract, not preflight regex.
- **Extending the gate to external plugins or consumers** outside this repo.
- **Retroactive remediation** of in-flight PRs authored before this merge — the gate applies to plans authored after merge only.

## Deferrals (tracked)

| Item | Issue | Re-eval criteria |
|---|---|---|
| CI workflow for user-brand-impact check | #2890 | Open immediately if first human-UI merge of sensitive-path change without section lands on main, OR a #2887-class post-merge incident recurs |
| AGENTS.md retirement audit (stale rule candidates) | #2891 | Next compound run reports AGENTS.md > 38.5k bytes |
| Threshold taxonomy review (collapse 3→2 levels?) | #2892 | Paying user count > 50, OR first real `aggregate pattern` threshold decision lands, OR <3 `aggregate pattern` labels in 12 weeks |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Checkbox/cargo-cult drift — sections filled with "users experience a bug" | High | `user-impact-reviewer` prompt contract requires specific artifact + vector; rejects generic boilerplate at review time. Monitor via quarterly grep (non-goal for this PR). |
| False-positive preflight blocks on README / comment-only edits under `apps/web-platform/**` | Medium | In-section scope-out note (`threshold: none, reason: <why>`) gives a 1-line override. Preflight interactive mode prompts user to add the note. |
| AGENTS.md crosses 37k warn threshold post-merge | Certain (accepted) | Compound nag at next run; #2891 tracks retirement audit. 40k critical still has 2.6k headroom. |
| Humans merging via GitHub UI bypass preflight gate | Certain (accepted) | Known gap per brainstorm decision #9; #2890 closes via CI. Documented in Non-Goals. |
| CPO becomes bottleneck on `single-user incident` sign-off | Low (current user count) | Revisit when >2 PRs/week get labeled; escalate security-sentinel as co-signer. |
| Brainstorm Phase 0.1 question becomes ceremony-only (users click through without thinking) | Medium | Trigger-keyword parser catches answers that explicitly name user-data/credentials/payment — even rote answers trigger the escalation if the keywords show up. If they don't, the session genuinely isn't user-brand-critical. |
| Agent description budget overrun | Low | Pre-commit run of `bun test plugins/soleur/test/components.test.ts` catches this. Target: add the agent's description at ~55 words; cumulative stays ≤2500. |
| Synthetic smoke plan accidentally pushed to main | Low | Underscore prefix; final cleanup task (G4) deletes it; pre-commit gitignore optional. |

## Implementation Dependencies

```
A1 (rule) ──┐
A2 (agent) ─┼─→ B (plan section) ─→ C (deepen halt) ─→ D (review) ─→ E (preflight) ─→ F (brainstorm 0.1) ─→ G (smoke) ─→ H (ship)
            │
            └─ No cross-dep between A1 and A2 (can commit separately)
```

Phase B must come before Phase C (halt greps for the section). Phase D references the agent file created in A2. Phase E can technically run before D but bundled for review coherence. Phase F intentionally last because the smoke scenario does not exercise brainstorm — the brainstorm gate is complementary, not load-bearing.

## References

- **Triggering incident:** #2887 (dev/prd Doppler configs at same Supabase project)
- **Parent issue:** #2888 (this plan's canonical source of truth)
- **Deferral issues:** #2890, #2891, #2892
- **Draft PR:** #2889
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-24-target-user-impact-gate-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-user-impact-gate/spec.md`
- **Functional discovery result:** registries checked (api.claude-plugins.dev, claudepluginhub.com, anthropics/claude-plugins-official) — zero functional match; this gate is novel
- **Related AGENTS.md rules:** `cq-agents-md-why-single-line` (byte budget), `cq-rule-ids-are-immutable` (ID handling), `cq-destructive-prod-tests-allowlist` (closest existing blast-radius framing), `wg-when-a-feature-creates-external-resources` (black-box probe shipping gate), `rf-review-finding-default-fix-inline` (scope-out labeling convention)
- **Template files for cross-reference:**
  - Phase 4.5 firewall halt → `plugins/soleur/skills/deepen-plan/SKILL.md` lines 299-317
  - security-sentinel agent format → `plugins/soleur/agents/engineering/review/security-sentinel.md`
  - Preflight Check structure → `plugins/soleur/skills/preflight/SKILL.md` lines 42-192
  - Review conditional_agents XML → `plugins/soleur/skills/review/SKILL.md` lines 102-176
