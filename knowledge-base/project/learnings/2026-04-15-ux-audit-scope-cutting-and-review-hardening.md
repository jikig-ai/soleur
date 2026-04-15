---
title: ux-audit skill — scope-cutting patterns and review-driven hardening
date: 2026-04-15
category: workflow-issues
tags: [plan-skill, fixture-design, review-gates, workflow-security, scope-cuts]
status: applied
pr: 2346
issue: 2341
synced_to: [plan, AGENTS.md]
route_to_definition_issues: [2363, 2364, 2365, 2366]
---

# Learning: ux-audit skill scope-cutting and review-driven hardening

## Problem

Shipping the `soleur:ux-audit` skill (PR #2346, owns #2341, blocks #2342) produced two scope surprises at implementation time and three near-shipping defects that only the review layer caught. The plan was structurally sound but carried two hidden assumptions about the surrounding system, and the first implementation pass accumulated three defects that were subtle enough to pass local tests but would have degraded production.

The narrative worth keeping: **which defects warrant a durable workflow change, and which are one-off learnings.**

## What shipped

4 commits on branch `collapsible-navs-ux-review`:

1. `cf1bf622` Phase 1 — Supabase bot user + Doppler secrets + DB-only fixture script + 5 tests
2. `830a0afc` Phase 2 — SKILL.md + route-list.yaml + bot-signin.ts + dedup-hash.ts + ux-design-lead audit-mode section + 8 tests
3. `66a0716e` Phase 3 — scheduled-ux-audit.yml workflow + triage/bug-fixer exclusions + expense ledger + plugin metadata
4. `be39614d` Review fixes — P1+P2 corrections from security-sentinel, architecture-strategist, code-quality-analyst, agent-native-reviewer, pr-test-analyzer

9 follow-up GitHub issues filed (2 deferrals + 7 P2/P3 review findings): #2351, #2352, #2356–#2362.

## Two scope surprises caught at implementation

### 1. Plan prescribed a golden-set test built from a corpus that doesn't exist

Plan Phase 2 required "3 historical UX issues that `ux-design-lead` audit-mode MUST surface from their relevant screenshots" picked via `gh issue list --label ux --state closed --limit 20`. Running the query during Phase 2 returned **zero** issues — the `ux` label doesn't exist in this repo (only `ux-audit`, created by this PR). Broader search for closed UI-fix PRs with screenshot attachments in their body: also zero matches.

The golden-set test was intended as a deterministic pass/fail gate before live calibration. Without a historical corpus it can't be built without circularly validating the rubric against the same pages it's being calibrated on.

**Resolution:** Deferred via #2352. Phase 3 Calibration becomes the single validation path until 3+ real `ux-audit` issues land with acknowledged fixes.

### 2. Plan prescribed KB seeding that requires OAuth-gated workspace provisioning

Plan Phase 1 required a 6-file KB tree (PDF, md, CSV, TXT, image, docx) seeded by `bot-fixture.ts`. Exploration revealed KB files don't live in Supabase — they're committed to a user's **GitHub workspace repo**, populated via the web-platform's `POST /api/kb/upload` which pushes to GitHub Contents API. Seeding requires provisioning the bot a real GitHub workspace repo with a GitHub App install (OAuth consent required, not automatable in a fixture script).

**Resolution:** Deferred via #2351. Fixture ships as DB-only v1; `/dashboard/kb` renders empty state under bot auth. Calibration target (#2342 collapsible-nav on `/dashboard`) is visible with or without KB content.

### Pattern behind both

Plans that cite an external corpus or seed an external system must **verify the corpus / classify the data-plane architecture at plan time**, not at implementation time. Both deferrals were clean — cut scope, file tracking issue, keep the critical path moving — but catching them during planning would have saved a round of scope negotiation mid-implementation.

Routing proposals:

- `plugins/soleur/skills/plan/SKILL.md` — pre-freeze acceptance criteria, run the `gh`/shell query that any corpus-citing AC implies; refuse to freeze the AC if the corpus query returns zero.
- `plugins/soleur/skills/plan/SKILL.md` or `plugins/soleur/skills/brainstorm/SKILL.md` — for each entity listed in a fixture spec, classify "DB-only" / "external service" / "hybrid" before freezing the spec.

## Three near-ship defects caught by review

### 1. SKILL.md documented an invalid CLI invocation

The skill's own Invocation section showed `claude code --skill soleur:ux-audit --route /dashboard`. `--skill` is not a valid Claude Code CLI flag. Another agent reading the skill and trying to orchestrate it would have failed on first try.

**Fix:** documented the correct forms — slash command (`/soleur:ux-audit`) inside a Claude Code session, `Skill(skill: "soleur:ux-audit", args: ...)` from another agent, and the workflow-dispatch path for CI.

### 2. Workflow `allowedTools` included `mcp__playwright__browser_evaluate`

`browser_evaluate` runs arbitrary JavaScript in the authenticated bot's browser context — session-cookie exfiltration, localStorage reads, authenticated API calls. The skill's SKILL.md references only `navigate`, `take_screenshot`, `resize`, `close`, `wait_for`; `evaluate` is not load-bearing. With prompt injection from a rendered page (audit targets live UIs), `evaluate` converts a content-injection into session exfiltration.

**Fix:** dropped `browser_evaluate` from the workflow's `claude_args --allowedTools`. Principle: **workflow allowedTools must be the narrowest set the skill actually uses, not a generous superset**.

### 3. Test assertion was tautologically true

`bot-fixture.test.ts` asserted `expect(["active", "none"]).toContain(row.subscription_status)` after running `seed`. Since `users.subscription_status` defaults to `"none"`, a `seed` that silently no-ops (e.g., if the PATCH fails and is swallowed) leaves the column at `"none"` — and the assertion still passes. The test name "seed unlocks middleware guards" was aspirational, not enforced.

**Fix:** tightened to `expect(row.subscription_status).toBe("active")`. Principle: **assertions verifying a mutation must pin the exact post-state value**, never membership in a set that includes the pre-state default.

### 4. Test `beforeAll` reset had no blast-radius guard

`bot-fixture.test.ts` ran `runScript("reset")` in `beforeAll` against **production Supabase** without validating that `UX_AUDIT_BOT_EMAIL` actually resolves to the synthetic bot. A mis-set env var (Doppler config mix-up, local export typo) would have deleted every conversation for whatever user the email resolved to.

**Fix:** added a pre-test assertion that throws if `UX_AUDIT_BOT_EMAIL !== "ux-audit-bot@jikigai.com"`, refusing to run before any DELETE. Also added a CI-only loud-fail when creds are absent (previously silent-skipped). Principle: **tests that DELETE against shared prod must gate on an allowlist of synthetic identifiers**; unguarded resets are blast-radius violations.

## Why durable workflow changes matter more than one-off learnings

Per `wg-every-session-error-must-produce-either`: documenting an error without routing it into a durable fix is a workflow violation. The test-assertion tautology (#3) and the blast-radius guard (#4) were caught by review agents — the *second* time. If review agents hadn't run, both would have shipped. The pattern that matters: **review catches are deterministic, memory is not**. Turn the caught pattern into a rule or a hook so the next session never writes the same defect.

Proposals (all headless-routed as issues or covered by the route-to-definition step below):

- **Code Quality rule candidate:** assertions verifying a mutation must pin the exact post-state value (not `toContain` with a set that includes the default).
- **Code Quality rule candidate:** tests running DELETEs against shared prod must assert on an allowlist of synthetic identifiers before any destructive call.
- **Workflow allowlist baseline:** workflows invoking `claude-code-action` with `mcp__playwright__*` must enumerate the minimal tool set; `browser_evaluate` requires explicit security-sentinel sign-off.
- **Skill scaffolding template:** SKILL.md Invocation section must use the canonical forms (slash + Skill-tool + workflow), never `claude code --skill`.

## Session Errors

Enumerated per the compound Phase 0.5 hard rule. Every item has a Recovery line and a Prevention line.

1. **First Supabase user creation used `__PASS__` literal instead of generated password.** First `curl --data-binary @-` heredoc was followed by a `PAYLOAD=$(jq -cn --arg ...)` rewrite, but the first curl had already fired against the admin API. User got created with the literal `__PASS__` string as password.
   **Recovery:** `PUT /auth/v1/admin/users/<id>` with the real password via admin API.
   **Prevention:** compose JSON payloads via `jq -cn --arg` in a variable **before** invoking curl; never mix heredoc with variable substitution in a single step.

2. **PreToolUse `security_reminder_hook.py` blocked two sequential workflow Edits, then succeeded on retry.** The hook prints advisory text about untrusted inputs but returns a "hook error" that blocks the Edit tool on some attempts and not others (same file, same session).
   **Recovery:** retried the Edit after reading the file fresh.
   **Prevention:** the hook's block-vs-advise decision logic is unclear from output alone; worth auditing whether it's supposed to block-always (reminder only) or allow-on-retry. If the former, the hook description should say "blocks once, remind-and-allow after" or similar.

3. **Plan Phase 2 golden-set test required a corpus that doesn't exist.** Zero closed `ux`-labeled issues, zero PRs with body screenshots.
   **Recovery:** deferred via #2352, plan updated in same commit, Phase 3 Calibration promoted to single validation path.
   **Prevention:** plan skill pre-freeze AC check — for any acceptance criterion that cites a corpus (`gh issue list --label X ...`), run the query and refuse to freeze the AC if the corpus is empty.

4. **Plan Phase 1 KB fixture specified Supabase seeding when files actually live in GitHub workspace.** Required OAuth-gated App install, not automatable in a script.
   **Recovery:** DB-only v1 shipped, KB seeding deferred via #2351, plan updated.
   **Prevention:** plan/brainstorm skill — for each entity in a fixture spec, classify "DB-only" / "external service" / "hybrid" at plan time.

5. **SKILL.md Invocation section used `claude code --skill` (invalid CLI flag).** Caught by agent-native-reviewer.
   **Recovery:** rewrote Invocation section with canonical forms (slash, Skill-tool, workflow).
   **Prevention:** plugin-level SKILL.md template should seed an Invocation section with the three canonical forms; skills that edit it must keep at least one valid form.

6. **Workflow `allowedTools` included `mcp__playwright__browser_evaluate`** (prompt-injection session-exfiltration vector, not referenced by SKILL.md). Caught by security-sentinel.
   **Recovery:** dropped `browser_evaluate` from the `--allowedTools` arg.
   **Prevention:** workflow scaffolding should seed minimal Playwright allowlist; security-sentinel gate on additions.

7. **Test assertion `expect(["active", "none"]).toContain(subscription_status)` was tautologically true after seed** — passed on seed no-op. Caught by code-quality-analyst.
   **Recovery:** tightened to `.toBe("active")`.
   **Prevention:** Code Quality rule candidate — mutation assertions must pin the exact post-state value.

8. **`beforeAll` ran reset against prod Supabase without guarding `UX_AUDIT_BOT_EMAIL`.** Mis-set env would have wiped real user data. Caught by pr-test-analyzer.
   **Recovery:** added pre-test `throw` guard against any email other than the synthetic bot; added CI-only loud-fail when creds absent.
   **Prevention:** Code Quality rule candidate — destructive tests against shared prod must gate on a synthetic-identifier allowlist.

9. **Agent-native-reviewer false-positive flagged `scripts/*.ts` as "missing".** Files existed in both worktree and pushed branch. Agent inferred absence from an incomplete file-tree read instead of verifying with `git ls-tree origin/<branch>`.
   **Recovery:** verified via `git ls-tree` inline, dismissed the finding, marked it retracted in the synthesis.
   **Prevention:** review agents claiming a file is "missing" must verify via `git ls-tree origin/<branch> -- <path>` before reporting. Low-grade but persistent false-positive pattern worth addressing in the review agent's instructions.

## Key Insight

**Scope cuts discovered during implementation are cheap if the plan structure supports them.** Both deferrals (#2351, #2352) turned into one-commit plan edits + one `gh issue create` each, with clean forward-pointers. The critical path (ship #2341, unblock #2342 via calibration) remained intact. The only cost was a round of user confirmation — the plan's own "scope question" structure (Option A / B / C with tradeoffs) made that confirmation fast.

**Review catches are deterministic; memory is not.** Three of the four near-ship defects (invocation docs, workflow allowlist, tautological assertion) are pattern-level — the same mistake reproduces across sessions unless a rule, hook, or template enforces otherwise. The blast-radius guard (#4) is general enough to become a rule. File the rule proposals; don't rely on the next session remembering.

## Related

- #2341 (owns), #2342 (blocked by), #2343 (TR4 deferral pinned), #2344 (auto-fix exclusion one-liners satisfied)
- #2351 (KB workspace seeding deferred), #2352 (golden-set test deferred)
- #2356–#2362 (7 code-review polish issues)
- Sibling learnings from same session: `2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`, `2026-04-15-plan-skill-tasks-before-review-ordering.md`

## Tags

category: workflow-issues
module: plan-skill, ux-audit, ship-review
