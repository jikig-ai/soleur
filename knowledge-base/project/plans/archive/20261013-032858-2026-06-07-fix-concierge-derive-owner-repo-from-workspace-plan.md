---
title: "fix: Concierge derives owner/repo from active workspace (stop prompting for repo)"
type: fix
date: 2026-06-07
branch: feat-one-shot-concierge-workspace-repo-context
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Concierge derives owner/repo from the active workspace

## Enhancement Summary

**Deepened on:** 2026-06-07
**Sections enhanced:** Research Insights added; all source attributions + premise verified live.

### Key Improvements
1. Verified every load-bearing file:line attribution against current source (no drift):
   `soleur-go-runner.ts:148` (directive) + `:158` (`remote.origin.url`),
   `agent-runner.ts:1433` (`The connected repository is ${owner}/${repo}` precedent),
   `cc-dispatcher.ts:260` (`GH_403_PROMPT_DIRECTIVE`), `:1323-1337` (owner/repo parse),
   `:1330` (`CC_GITHUB_NAME_RE` validation), `:1532` (unconditional append precedent).
2. Confirmed the package test runner is **vitest** (not bun) and pinned the exact run
   command + test placement (`test/**/*.test.ts` → node project) — closes the bun-vs-vitest
   sharp edge before /work.
3. Verified the two negative security claims (owner/repo never tool-tainted; token never
   in the owner/repo string) against source.

### New Considerations Discovered
- `apps/web-platform/bunfig.toml:11` has `pathIgnorePatterns = ["**"]` — `bun test <file>`
  reports "filter did not match" even for existing tests. The implementer MUST use vitest.
- The cc-path system prompt is assembled in TWO places: the baseline directive lives in
  `soleur-go-runner.ts` (`buildSoleurGoSystemPrompt`), but the per-dispatch owner/repo
  addendum must live in `cc-dispatcher.ts` (the factory) — the ONLY scope where
  `connectedOwner`/`connectedRepo` exist. Both files must change.

### Research Insights

**Precedent-diff (Phase 4.4) — pattern is NOT novel; two in-repo precedents:**

- *System-prompt addendum injection*: `cc-dispatcher.ts:1532` appends `GH_403_PROMPT_DIRECTIVE`
  unconditionally; `:1527-1529` appends `c4PromptAddendum` conditionally inside a guard. The
  new connected-repo addendum mirrors the conditional form (guard:
  `connectedOwner && connectedRepo`).
- *Naming the connected repo to the agent*: `agent-runner.ts:1429-1441` (leader path) already
  emits `## GitHub read access\n\nThe connected repository is ${owner}/${repo}.` — the cc path
  simply lacks the equivalent. Lock-step the lead phrase `The connected repository is
  ${owner}/${repo}` so both surfaces stay greppable together.
- *Injection-safety precedent*: `agent-runner.ts:1425-1428` documents that owner/repo are
  `GITHUB_NAME_RE`-validated and "If that regex ever relaxes, this becomes a prompt-injection
  sink." `cc-dispatcher.ts` validates identically via `CC_GITHUB_NAME_RE` at `:1330`. Carry the
  same warning comment to the new builder.

**Verified test command (AC6):**

```bash
# Runner is vitest (apps/web-platform/package.json scripts.test = "vitest").
# New test MUST live under test/ (node project include: "test/**/*.test.ts").
# Do NOT use `bun test` — apps/web-platform/bunfig.toml:11 pathIgnorePatterns=["**"].
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/cc-dispatcher-connected-repo-context.test.ts \
  test/soleur-go-runner-gh-auth-status.test.ts
```

**Premise + attribution verification (live, 2026-06-07):**

```text
gh issue view 4826 → OPEN "feat: nav-rail position resume …"  (example trigger, not blocker)
gh issue view 3242/3243/3454 → all OPEN (code-review overlaps; acknowledged, not folded in)
grep remote.origin.url soleur-go-runner.ts → :158 (the clause to rewrite)
grep "The connected repository is" agent-runner.ts → :1433 (precedent confirmed)
grep connectedOwner/CC_GITHUB_NAME_RE.test/effectiveSystemPrompt cc-dispatcher.ts → :1323/:1330/:1532
```

## Overview

In the Dashboard "Soleur Concierge" chat, asking to **"Fix Issue 4826"** makes the
Concierge reply that **there is no connected git repository** — it claims `gh` cannot
infer the repo and there is no `.git` directory, then asks the user to provide
`owner/repo`. This is wrong: the active workspace already has the repo connected
(`jikig-ai/soleur` per the workspace header), and the server already knows the
owner/repo for the dispatch.

**Root cause (verified against current source):** The Concierge router runs through
`soleur-go-runner.ts` → `cc-dispatcher.ts` (the `realSdkQueryFactory`). The router's
baseline system prompt embeds `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE`
(`apps/web-platform/server/soleur-go-runner.ts:148-159`), which instructs the agent to
**"discover your owner/repo from the origin remote with `git config --get
remote.origin.url`"**. When the workspace has no `.git` (cold workspace, or the
`ensureWorkspaceRepoCloned` self-heal failed/has not run), that command returns nothing,
so the agent concludes "no repo connected" and falls back to prompting the user.

Meanwhile, the **server already resolves and validates the owner/repo** for every
dispatch: `cc-dispatcher.ts:1323-1337` parses `connectedOwner`/`connectedRepo` from the
membership-scoped `getCurrentRepoUrl(userId)` (active-workspace repo URL, ADR-044) and
validates each against `CC_GITHUB_NAME_RE`. These values are *already in scope* in the
factory and are reused for the GH_TOKEN mint + the C4 write-tool gate — they are simply
never surfaced into the Concierge's system prompt.

The sibling leader path already does the right thing: `agent-runner.ts:1429-1441` appends
`## GitHub read access\n\nThe connected repository is ${owner}/${repo}. …` to its system
prompt. The Concierge (cc path) has no equivalent. **The fix is to mirror that pattern in
the cc path** and to retire the "discover owner/repo from the git origin remote"
instruction that produces the false "no repo connected" reply.

**Approach (minimal, mirrors existing patterns):**

1. In `cc-dispatcher.ts` `realSdkQueryFactory`, when `connectedOwner && connectedRepo`
   are non-empty (already resolved at `:1323-1337`), append a **connected-repo context
   addendum** to `effectiveSystemPrompt` — byte-shaped exactly like the unconditional
   `GH_403_PROMPT_DIRECTIVE` append at `:1532` and the conditional `c4PromptAddendum`
   append at `:1527-1529`. The addendum states the connected repo as `owner/repo` and
   instructs the agent to pass `-R owner/repo` using **that** value (never inferring from
   a git remote).
2. In `soleur-go-runner.ts`, **rewrite the owner/repo-discovery clause** of
   `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` so the baseline no longer tells the agent to derive
   owner/repo from `git config --get remote.origin.url`. The baseline keeps the
   installation-token / `gh auth status` false-negative guidance (still load-bearing) but
   points at "the connected repository named in your context" for the `-R owner/repo`
   value. The dispatcher-injected addendum (item 1) supplies that name.

This keeps the server as the single source of truth for owner/repo (it is the only
trustworthy source — `repo_url` is membership-scoped and validated), removes the
git-origin dependency that breaks on a `.git`-less workspace, and changes **prompt text
only** — no new infra, no schema, no new runtime data path.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Reality (verified in source) | Plan response |
| --- | --- | --- |
| "concierge says no connected git repository … `gh` can't infer the repo, no `.git`" | The baseline directive at `soleur-go-runner.ts:157` tells the agent to derive owner/repo from `git config --get remote.origin.url`; a `.git`-less workspace makes that return empty → false "no repo" conclusion. | Rewrite the directive's owner/repo-discovery clause; inject server-resolved owner/repo. |
| "the workspace already has the repo connected (jikig-ai/soleur)" | True: `getCurrentRepoUrl(userId)` (active-workspace `repo_url`, ADR-044) is resolved at `cc-dispatcher.ts:1250` and parsed to `connectedOwner`/`connectedRepo` at `:1323-1337`. | Surface those already-resolved values into the system prompt. |
| "should derive owner/repo from current workspace context" | The leader path already does this (`agent-runner.ts:1429-1441`); the cc/Concierge path does not. | Mirror the leader's `The connected repository is ${owner}/${repo}` addendum in the cc path. |
| Issue #4826 is the issue to fix | #4826 is a real OPEN issue ("feat: nav-rail position resume …") — unrelated to this bug; it is only the example the user typed to trigger the broken reply. `gh issue view 4826` succeeds. | No premise change. The fix is the Concierge repo-context, not #4826 itself. |

**Premise Validation:** The cited issue (#4826) exists and is OPEN; it is an example trigger,
not a blocker. The cited symptom ("`gh` can't infer the repo / no `.git`") maps to a real
baseline directive (`soleur-go-runner.ts:157`) that depends on a git origin remote. The
claim "the workspace already knows the repo" is confirmed: `connectedOwner`/`connectedRepo`
are resolved and validated server-side at `cc-dispatcher.ts:1323-1337`. No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge continues to deny that a
repo is connected and asks them to type `owner/repo` (or worse, the agent passes a wrong
`-R` value and `gh` 404s the issue), so the single most-marketed Concierge flow
("Fix Issue N") is a dead end on a workspace that visibly shows the repo in its header.

**If this leaks, the user's data/workflow is exposed via:** the owner/repo string injected
into the prompt is the user's own active-workspace `repo_url` — already validated by
`CC_GITHUB_NAME_RE` and never tool-tainted. The risk is **mis-pairing**, not leakage: a
concurrent `set_current_workspace_id` switch could pair workspace A's repo name with a
later dispatch — same sub-ms window already documented at `cc-dispatcher.ts:1323-1337` and
out of scope here. No new exposure vector; both repos belong to the SAME user.

**Brand-survival threshold:** single-user incident — the Concierge is the flagship
agent-native surface; a user whose repo is plainly connected being told "no repo
connected" is a trust-eroding, brand-survival-class failure for that one user.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Server injects connected-repo context (cc path).** When `connectedOwner` and
  `connectedRepo` are both non-empty, `cc-dispatcher.ts` appends a system-prompt addendum
  naming the connected repository as `${connectedOwner}/${connectedRepo}` and instructing
  the agent to use that value for `-R owner/repo`. Verify by source-presence test (the
  factory is impractical to invoke in a unit test — same framing as the existing
  `cc-dispatcher-gh-403-directive.test.ts`): the addendum constant exists, carries the
  `${connectedOwner}/${connectedRepo}` interpolation and an `-R` reference, and is appended
  to `effectiveSystemPrompt` inside the `if (connectedOwner && connectedRepo)` guard.
- [x] **AC2 — Baseline directive no longer tells the agent to infer owner/repo from the git
  origin remote.** `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` in `soleur-go-runner.ts` MUST NOT
  contain the substring `remote.origin.url`. It MUST still contain the paren-safe anchors
  `gh auth status` and `-R owner/repo` (the existing
  `soleur-go-runner-gh-auth-status.test.ts` anchors stay green) and MUST reference the
  connected repository named in the agent's context.
- [x] **AC3 — Addendum injection is guarded on resolved owner/repo, not on a `.git`
  presence check.** The new addendum append is inside the `connectedOwner && connectedRepo`
  truthiness guard (server-resolved values), NOT gated on `existsSync(.git)` — so it fires
  even on a `.git`-less workspace (the exact failing case).
- [x] **AC4 — Owner/repo interpolation is injection-safe.** The plan reuses
  `connectedOwner`/`connectedRepo`, which are validated against `CC_GITHUB_NAME_RE` at
  `cc-dispatcher.ts:1330` before assignment. A test asserts the addendum builder is fed
  only those validated bindings (no raw `repoUrl`, no tool input). Mirror the
  `agent-runner.ts:1425-1428` safety comment.
- [x] **AC5 — No behavioral change when no repo is connected.** When `connectedOwner`/
  `connectedRepo` are empty (no connected repo / non-member), the addendum is NOT appended
  and the prompt is byte-identical to today's (graceful degradation parity with the
  existing GH_TOKEN no-op). Source/test assertion that the append sits inside the guard.
- [x] **AC6 — `tsc --noEmit` and the web-platform test suite pass.** Run via the package's
  actual runner (`apps/web-platform` uses vitest — confirm via `package.json scripts.test`
  before running; place new tests under `apps/web-platform/test/` per the repo's vitest
  `include:` globs, not co-located).

### Post-merge (operator)

- [ ] **AC7 — Live Concierge smoke (automatable via Playwright MCP).** In the Dashboard
  Concierge on a workspace connected to `jikig-ai/soleur`, send "Fix Issue 4826"; assert the
  reply does NOT claim "no connected git repository" / "provide owner/repo" and that the
  agent routes the issue through the fix workflow (or reads the issue via `gh … -R
  jikig-ai/soleur`). Automation: `mcp__playwright__*` against the dashboard.
  `Automation: feasible` — do not punt to a manual operator step.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts`
  - Add a `CONNECTED_REPO_CONTEXT` directive builder (module-scope `const` or small
    `function`, mirroring `GH_403_PROMPT_DIRECTIVE` at `:260-271`) that takes validated
    `owner`/`repo` and returns the `## Connected repository` block stating
    `The connected repository is ${owner}/${repo}. For any repo gh operation, pass -R
    ${owner}/${repo}` (lock-step wording with `agent-runner.ts:1429-1441`).
  - In `realSdkQueryFactory`, after the `GH_403_PROMPT_DIRECTIVE` append (`:1530-1532`),
    add: `if (connectedOwner && connectedRepo) { effectiveSystemPrompt += \`\n\n${builder(connectedOwner, connectedRepo)}\`; }`.
    Add the `agent-runner.ts:1425-1428`-style injection-safety comment (owner/repo are
    `CC_GITHUB_NAME_RE`-validated; if that regex relaxes this becomes an injection sink).
- `apps/web-platform/server/soleur-go-runner.ts`
  - Rewrite the trailing clause of `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` (`:148-159`):
    remove `discover your owner/repo from the origin remote with git config --get
    remote.origin.url` (and the `gh cannot infer it without -R owner/repo` sentence that
    frames git-origin discovery). Replace with guidance to use **the connected repository
    named in your context** for `-R owner/repo`. Keep the `gh auth status` false-negative
    guidance and both paren-safe anchors (`gh auth status`, `-R owner/repo`) intact.

## Files to Create

- `apps/web-platform/test/cc-dispatcher-connected-repo-context.test.ts` — source-presence
  test for AC1/AC3/AC4/AC5 (mirrors `cc-dispatcher-gh-403-directive.test.ts` shape: read
  `cc-dispatcher.ts`, assert the directive constant/builder exists with the
  `${connectedOwner}/${connectedRepo}` interpolation + `-R` reference, and that the append
  is inside the `connectedOwner && connectedRepo` guard).
- Extend `apps/web-platform/test/soleur-go-runner-gh-auth-status.test.ts` (existing file)
  with an AC2 assertion: `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` does NOT contain
  `remote.origin.url` and still contains both paren-safe anchors.

## Test Scenarios

1. **Connected repo, `.git`-less workspace (the failing case):** `connectedOwner`/
   `connectedRepo` resolve from `repo_url`; addendum is appended; agent has owner/repo
   without touching a git remote. (Source/integration assertion + post-merge Playwright.)
2. **No connected repo:** addendum NOT appended; prompt byte-identical to today (AC5).
3. **Baseline directive:** no `remote.origin.url`; anchors `gh auth status` + `-R
   owner/repo` still present (AC2).
4. **Injection safety:** addendum fed only `CC_GITHUB_NAME_RE`-validated bindings (AC4).

## Open Code-Review Overlap

2 open scope-outs name `cc-dispatcher.ts` and 2 name `agent-runner.ts`:
- **#3243** (arch: decompose cc-dispatcher.ts into focused modules) — **Acknowledge.**
  Different concern (file decomposition); this fix adds one guarded append, not a
  refactor. Folding the decomposition in would balloon scope. Remains open.
- **#3242** (review: tool_use WS event lacks raw name field) — **Acknowledge.** Unrelated
  to system-prompt repo context (WS event shape). Remains open.
- **#3454** (review: expose pdf_metadata as agent-callable MCP tool) — **Acknowledge.**
  Unrelated (PDF tooling on the leader path). Remains open.

None of the four touch the system-prompt owner/repo assembly this fix targets.

## Observability

```yaml
liveness_signal:
  what: "Concierge dispatch completes and routes 'Fix Issue N' through the fix workflow (no 'no repo connected' reply)"
  cadence: "per Concierge dispatch (interactive)"
  alert_target: "existing chat-write-absence alert (knowledge-base/project/brainstorms/2026-06-03-chat-write-absence-alert-brainstorm.md) — no new alert needed"
  configured_in: "existing cc-dispatcher Sentry breadcrumbs"
error_reporting:
  destination: "Sentry via reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry)"
  fail_loud: "owner/repo resolution failure already mirrors at cc-dispatcher.ts:1340-1349 (repo_url present but null installation) and the malformed-repoUrl catch at :1334-1336 degrades silently by design (no owner/repo → no addendum, same as no-repo case)"
failure_modes:
  - mode: "repo_url present, owner/repo parse fails (malformed URL)"
    detection: "no addendum appended → agent degrades to existing baseline behavior"
    alert_route: "none (benign degrade; pre-existing malformed-repoUrl catch)"
  - mode: "repo_url present, installation null (revoked grant)"
    detection: "existing reportSilentFallback at cc-dispatcher.ts:1340-1349"
    alert_route: "Sentry (existing)"
  - mode: "prompt addendum present but model still refuses"
    detection: "post-merge Playwright smoke (AC7) + chat-write-absence alert"
    alert_route: "Sentry / existing chat alert"
logs:
  where: "cc-dispatcher childLogger (pino) — existing dispatch breadcrumbs; owner/repo NEVER includes token (GH_TOKEN excluded)"
  retention: "existing pino/Sentry retention"
discoverability_test:
  command: "grep -n 'connected repository is' apps/web-platform/server/cc-dispatcher.ts && ./node_modules/.bin/vitest run apps/web-platform/test/cc-dispatcher-connected-repo-context.test.ts"
  expected_output: "directive constant present; test passes (NO ssh)"
```

## Domain Review

**Domains relevant:** Product (Concierge UX), Engineering (prompt assembly).

### Product/UX Gate

**Tier:** none (orchestration/prompt-text change; no new UI surface, no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx` file in Files to Create/Edit). The Concierge
chat UI is unchanged — only the agent's server-side system prompt text changes.
**Decision:** auto-accepted (pipeline) — NONE tier, no wireframe required
(`wg-ui-feature-requires-pen-wireframe` does not fire: no UI-surface file touched).

#### Findings

The change is invisible in the DOM; the only user-visible effect is a *correct* Concierge
reply instead of the false "no repo connected" one. CPO sign-off is required at plan time
per the `single-user incident` threshold (frontmatter `requires_cpo_signoff: true`) —
confirm CPO has reviewed the approach (mirror the leader path, server-as-source-of-truth)
before `/work` begins. `user-impact-reviewer` runs at review-time per the threshold.

## Infrastructure (IaC)

No new infrastructure — pure prompt-text change against an already-provisioned surface
(`apps/web-platform/server/*`). No server, service, secret, vendor, DNS, cron, or
persistent runtime process introduced. Phase 2.8 gate: skip.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with the `single-user incident` threshold.)
- **Lock-step the addendum wording with `agent-runner.ts:1429-1441`.** The leader path
  already says `The connected repository is ${owner}/${repo}`. Use the same lead phrase so
  the two surfaces stay greppable together and a future copy edit to one is easy to mirror.
- **Do NOT gate the addendum on `.git` presence.** The entire bug is that the agent
  depends on a git artifact that may be absent; the server-resolved owner/repo is the
  authoritative source. Gate only on `connectedOwner && connectedRepo` truthiness.
- **`GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` anchors are paren-safe and asserted by an existing
  test.** When rewriting the directive, keep the literal tokens `gh auth status` and
  `-R owner/repo` intact (no punctuation straddling the phrase) or
  `soleur-go-runner-gh-auth-status.test.ts:33,38` will fail.
- **Owner/repo interpolation is a prompt-injection sink IF `CC_GITHUB_NAME_RE` relaxes.**
  The addendum is only safe because owner/repo are regex-validated at `:1330`. Carry the
  `agent-runner.ts:1425-1428` warning comment forward to the new builder.
- The cc-path system prompt is assembled in `cc-dispatcher.ts` `effectiveSystemPrompt`
  (factory), NOT in `buildSoleurGoSystemPrompt` (runner). The baseline directive lives in
  the runner; the per-dispatch owner/repo addendum lives in the factory (only there are
  `connectedOwner`/`connectedRepo` in scope). Edit BOTH files accordingly.
