---
title: "Complete the broader ${CLAUDE_PLUGIN_ROOT} plugin-script migration (Slice C, ADR-093)"
date: 2026-07-07
type: fix
labels: [type/security, domain/engineering, deferred-scope-out, priority/p1-high]
closes: 6121
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-093 (amend)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure (no server, secret, vendor,
     systemd unit, cron, DNS, or runtime process). It is a pure SKILL.md-text + one-test change.
     The "operator-run" / "provisioning" wording below appears ONLY in the Scope Classification
     to explain why operator-run scripts are EXCLUDED from migration — it prescribes no manual
     infra step. No ## Infrastructure (IaC) section is required. -->

# 🔒 Complete the broader `${CLAUDE_PLUGIN_ROOT}` plugin-script migration (Slice C, ADR-093)

## Enhancement Summary

**Deepened on:** 2026-07-07 · **Review agents:** security-sentinel, spec-flow-analyzer, code-simplicity-reviewer (+ learnings-researcher).

### Key improvements applied from the deepen panel
1. **AC1 was a false-passing gate** (all 3 reviewers flagged) — its narrow `bash [^ ]*\./?…` grep can't match `bash plugins/…` (no-dot), no-`bash`, `../../`, or `$(git rev-parse…)` forms, i.e. the exact undercount class this slice closes. Rewritten to the broad Phase-0 pattern.
2. **Residual untrusted-exec surface was under-documented** — security-sentinel + spec-flow grep-proved additional agent-run families carry the identical hole (esp. `legal-generate:60` running the secret-**redaction gate**, `trigger-cron` prod-cron POST). AC11 residual list made exhaustive + honestly framed as OPEN with a P1 `type/security` follow-up.
3. **Cross-caller half-migration folded in** — `product-roadmap:29,39` calls the same `roadmap-reconcile.sh` as migrated `brainstorm:119`; leaving it was indefensible.
4. **Enumeration gaps closed** — `brand-workshop:5`, `validation-workshop:7` re-added; `brainstorm:37` split into its 2 invocations (2 anchors on one line); `pencil-setup:193` resolved to migrate; echo discriminator stated.
5. **Ceremony trimmed** (simplicity) — cut LARP ACs (AC4/AC8/AC12, AC10-C4→prose); coupling-test vacuity floor `≥4`→`≥1`; dropped speculative "any other read-only verb" clause.
6. **Wording fix** — corrected "every other migrated invocation is a write/compute verb" (some are read-only) while confirming none were ever safe-bash-auto-approved (no `bash <script>` matcher exists).

### New considerations surfaced
- The scope-expansion pressure is recorded as a **User-Challenge** in `decision-challenges.md` (operator's 14-family scope is the default; reviewers pushed to fold all in).
- **Verified sound (security-sentinel):** no new auto-approve/injection surface; server-side the `$(git rev-parse)` fallback never executes (var always set); `safe-bash.ts` needs zero code change.

## Overview

This is the **3rd / final PR** of the connected-repo plugin-shadow fix (ADR-093). It migrates the
remaining sandbox-executed, agent-run `bash ./plugins/soleur/skills/…/<script>.sh` invocations in the
non-wedge skill families to the deployment-anchored `${CLAUDE_PLUGIN_ROOT:-<local-fallback>}/…` form, and
adds the advisor-flagged **AC5↔AC6 coupling test** so future drift fails loudly.

**Prior slices (already MERGED + deployed — cited as prose, NOT work targets):**

- **Slice A** (merged): moved the SDK plugin load to `getPluginPath()` (both factories + `context-queries-hook.ts`), with `assertTrustedPluginPath` loaded-gun guard. ADR-093.
- **Slice B** (merged + deployed, squash `07652ae04`, PR #6142): added the `CLAUDE_PLUGIN_ROOT` per-dispatch env injection (`agent-env.ts` `pluginPath?` → `env.CLAUDE_PLUGIN_ROOT`, threaded from both factories via `agent-runner-query-options.ts` and `cc-dispatcher.ts`), the `safe-bash.ts` `EXACT_LITERAL_SAFE_COMMANDS` carve-out for `worktree-manager.sh list|ls`, the in-image `plugin-root-propagation` CI gate, and migrated the **7 wedge-flow sites** (`go.md:24,41`, `one-shot/SKILL.md:47,65`, `work/SKILL.md:43,85,163`).

**The security problem this closes.** Autonomous bash is default-on on the Concierge server
(`feat-bash-autonomous-default-on`, post first-run consent). Under that posture, the autonomous-bypass in
`permission-callback.ts` auto-approves any non-blocked command. So any un-migrated skill family that still
emits a **CWD-relative** `bash ./plugins/soleur/…/<script>.sh` executes the **connected repo's untrusted
committed copy** on the server, outside the bwrap tool sandbox. This is **untrusted-code execution**, not a
mere delivery gap (see the pinned #6121 verification comments). Slice A closed the SDK-load half; Slice B
closed the 7 wedge-flow sites + the env plumbing + the carve-out; **this slice closes the residual surface for
the 14 #6121-enumerated families (+ `product-roadmap`, folded in for cross-caller consistency)** and installs
the drift guard. A residual set of genuinely-distinct agent-run families (`legal-generate`, `trigger-cron`,
`incident`, and others — deepen-plan review surfaced these) still carries the identical hole and is deferred
to a P1 `type/security` follow-up (§Scope, AC11) — the PR body states this surface **remains open** until then.

**What this PR is NOT.** No changes to `agent-env.ts`, `agent-runner-query-options.ts`, `cc-dispatcher.ts`,
`plugin-path.ts`, or the propagation probe — those are Slice B, already live. **No fixture regeneration**
(the change is SKILL.md text + one new test; `CLAUDE_PLUGIN_ROOT` is NOT in the `--setenv` allowlist, so the
ADR-079 canary projection is byte-identical — provably canary-neutral).

## Research Reconciliation — Spec vs. Codebase

| Claim (task / #6121 body) | Reality (verified in worktree) | Plan response |
|---|---|---|
| "~9 sites across the non-wedge-flow families" | The narrow `bash [^ ]*plugins/soleur/skills/…\.sh` grep is an **undercount**. The broader `plugins/soleur/skills/[^ ]+\.sh` pattern (drop the `bash `-anchor) finds **env-prefixed** (`SOLEUR_SKILL_NAME=… ./plugins/…`), **no-`bash`-prefix direct execs** (`brainstorm/SKILL.md:344`), **`../../`-anchored** (`brainstorm/SKILL.md:37` from inside a worktree), and **git-root-anchored** (`compound/SKILL.md:289` via `$(git rev-parse --show-toplevel)`) forms the narrow grep misses. Real in-scope agent-run count ≈ **50–55 sites across 14 files** (git-worktree alone is 22). | Migration MUST use the broad pattern, then **classify each hit** (agent-exec vs prose vs the-operator-runs-it). §Scope Classification. |
| "ADD the exact deployed-form string to `EXACT_LITERAL_SAFE_COMMANDS`" | The `worktree-manager.sh list`/`ls` deployed-form literals are **ALREADY in the set** (Slice B: `${WORKTREE_MANAGER_DEPLOYED_FORM} list\|ls`). The only verbs auto-approved via safe-bash are those two exact literals — **`SAFE_BASH_PATTERNS` has NO general `bash <script>` matcher** (verified `safe-bash.ts:90-145`). So although several migrated invocations *are* read-only (`roadmap-reconcile.sh validate`, `community-router.sh platforms`, `check_deps.sh --check-adapter-drift` — corrected wording; not all are "write/compute"), **none of them were ever safe-bash-auto-approved** — they hit autonomous-bypass (server) / review-gate (CLI) before and after, and leaving them gated is the safe choice. The 4 git-worktree `list` sites (72,124,217,299) all use the `./` anchor → map to the single existing literal. | **No new `EXACT_LITERAL_SAFE_COMMANDS` entries are needed** and `safe-bash.ts` needs **zero code change** (deepen security-sentinel confirmed). Deliverable = the **coupling test** + security-sentinel sign-off that the carve-out covers every migrated `list`/`ls` emission. **Do NOT** widen the allowlist to admit the read-only script invocations — gated is correct. |
| "route the safe-bash.ts changes through security-sentinel" | Since safe-bash.ts is expected to be untouched, the security review target is the **migration's security posture + the coupling test**, not a safe-bash edit. | security-sentinel reviews the delta as-is (confirming no denylist weakening, no missed site leaves an untrusted-exec hole, carve-out completeness). |
| "compound token-efficiency-report.sh" | `compound/SKILL.md:289` uses `bash "$(git rev-parse --show-toplevel)/plugins/soleur/…"` — **git-root-anchored, not CWD-relative**. On the server `git rev-parse` resolves to the connected-repo root → still the untrusted copy. | Migrate with a **git-root-preserving fallback**: `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` (§Sharp Edges — per-site fallback rule). |
| Slice B B5 migrated go/one-shot/work | Confirmed via `git grep CLAUDE_PLUGIN_ROOT` — those 7 sites already carry the deployed form. | Out of scope here; do not re-touch. |

## User-Brand Impact

**If this lands broken, the user experiences:** a broken worktree/ship/brainstorm command — e.g. `bash: …/worktree-manager.sh: No such file or directory` when a migrated fallback resolves to the wrong path for that site's CWD (a CLI user in a worktree subdir), OR a `list` verb silently degrading to a review-gate prompt if its emitted form drifts out of `EXACT_LITERAL_SAFE_COMMANDS`.

**If this leaks, the user's workflow/code is exposed via:** a **missed** migration site — the Concierge agent auto-approves and runs the connected repo's **untrusted committed** `<script>.sh` on the server, outside the bwrap sandbox (arbitrary code execution as the platform, against another user's session). This is the exact residual surface #6121 tracks.

**Brand-survival threshold:** `single-user incident` — this is `type/security` and the failure mode is untrusted code execution on a shared server; one missed site is a per-user breach. `requires_cpo_signoff: true` (headless: recorded to `decision-challenges.md` for async CPO ack; `user-impact-reviewer` runs at review-time; deepen-plan security triad — security-sentinel + data-integrity-guardian + architecture-strategist — is warranted).

## Scope Classification (classify first — do NOT migrate all ~96 raw sites)

The raw `git grep -nE 'bash [^ ]*plugins/soleur/skills/[^ ]+\.sh' -- plugins/soleur/skills` returns ~96
hits across 46 files. **Only sandbox-executed, agent-run SKILL.md/reference-md invocations are in scope.**

**Migrate decision rule (a site is IN scope iff ALL hold):**
1. The Concierge **agent** is the executor of the command in the sandbox (or of an echoed command the *agent itself* then runs, e.g. a pencil-setup `--auto` instruction to the agent), AND
2. it is NOT purely descriptive prose that merely names a script path in a sentence (e.g. `ship/SKILL.md:605` gdpr-gate regex-mirror mention), AND
3. the **human, not the agent, is the executor** — a credential/provisioning setup command the skill only *displays* (run by the human on their own trusted local checkout; the server agent never executes it), AND
4. it is NOT a `.test.sh` (CI-run), a script invoked by another script, or a `.mjs`/`SETUP.md` artifact.

**Echo discriminator (two similar echoed forms get opposite dispositions — state it explicitly).** `brand-workshop:64` (`echo "Run: bash …/check_deps.sh --auto"`) is IN scope because the pencil-setup command is **agent-executed** (the agent runs it during setup). `community:75–78` (`"Run \`…/discord-setup.sh\`…"`) are OUT because the human is the executor of those credential setups — the agent only displays them. Rule: an echoed command is in-scope iff the *agent* is its executor.

### IN SCOPE — migrate (14 files, ≈50–55 agent-run sites)

| File | Script(s) / verbs | Notes |
|---|---|---|
| `git-worktree/SKILL.md` | `worktree-manager.sh` × 22 (create/list/switch/copy-env/cleanup/`--update-local-main` create/sync-bare-files) | The big one. `list` (4×) → matches existing carve-out. |
| `ship/SKILL.md` | `auto-close-scan.sh` (1149,1150,1151, `$(…)` capture), `worktree-manager.sh cleanup-merged` (2039) | **Exclude** :605 (prose). |
| `brainstorm/SKILL.md` | line 37 is **TWO** invocations (deepen spec-flow): `feature` (env-prefixed, no-`bash`, `./` anchor — runs on main pre-`cd`) **and** `draft-pr` (`bash ../../` anchor — runs inside worktree); plus `feature` (344, no-`bash`, `./`), `draft-pr` (367, `./`); `roadmap-reconcile.sh validate` (119); `check_deps.sh --auto` (429); `archive-kb.sh` (606) | **7 invocations across 6 lines** — line 37 needs two different fallbacks on one line. |
| `brainstorm/references/brainstorm-brand-workshop.md` | `worktree-manager.sh feature` (**5**, no-`bash`, `./`); `draft-pr` (22, `../../`); `check_deps.sh --auto` (64, agent-executed echo) | Line 5 was dropped in draft — re-added (deepen spec-flow HIGH). |
| `brainstorm/references/brainstorm-validation-workshop.md` | `worktree-manager.sh feature` (**7**, no-`bash`, `./`); `draft-pr` (24, `../../`) | Line 7 was dropped in draft — re-added (deepen spec-flow HIGH). |
| `merge-pr/SKILL.md` | `worktree-manager.sh cleanup-merged` (386) | |
| `drain-prs/SKILL.md` | `triage-prs.sh` (49); `worktree-manager.sh cleanup-merged` (102) | |
| `fix-issue/SKILL.md` | `worktree-manager.sh --yes create` (133) | |
| `archive-kb/SKILL.md` | `archive-kb.sh` (16,20,24) | |
| `deploy/SKILL.md` | `deploy.sh` (68) | Agent-run deploy skill (not the CI release pipeline). |
| `pencil-setup/SKILL.md` | `check_deps.sh` (23,29), `copy_adapter.sh` (101), `check_deps.sh --check-adapter-drift` (122), **:193** (the `bash …/check_deps.sh --check-adapter-drift` in the diagnosis bullet — **RESOLVED: migrate**, agent-executed; no longer "likely") | |
| `feature-video/SKILL.md` | `check_deps.sh` (37,43) | |
| `community/SKILL.md` | `community-router.sh platforms` (28,73) | **Exclude** :75–78 (credential-setup echoes: discord/x/bsky/linkedin-setup.sh — human is the executor). |
| `compound/SKILL.md` | `token-efficiency-report.sh` (289, **git-root fallback**); `archive-kb.sh` (455) | |
| `product-roadmap/SKILL.md` | `roadmap-reconcile.sh` (29,39) | **FOLDED IN** (deepen security+spec-flow P1): the SAME `roadmap-reconcile.sh` migrated via `brainstorm:119` — leaving product-roadmap's own caller un-migrated is an indefensible cross-caller half-migration. `./` anchor, zero marginal cost. |

### EXCLUDED — do NOT migrate (document why; some are a documented residual surface)

| Class | Files / sites | Reason |
|---|---|---|
| `.test.sh` (CI-run) | `compound/test/phase-16.test.sh`, `git-worktree/test/*.test.sh`, `linear-fetch/scripts/*.test.sh`, gdpr-gate self-test | Run by CI/test-all.sh, not the agent sandbox. |
| The-operator-runs-it / CI-run scripts | `provision-{cloudflare,doppler,github,hetzner}/SKILL.md`, `flag-{create,delete,list,set-role}` + `flag-bootstrap/SETUP.md`, `user-set-role`, `community/SKILL.md:75–78` setup echoes | Provisioning / flag mutation / credential setup run under operator ack on the operator's trusted checkout — the server agent never executes them. |
| Script-invoked-by-script / adapters | `pencil-setup/scripts/pencil-mcp-adapter.mjs`, `gdpr-gate/scripts/gdpr-gate.sh` (invoked by ship/preflight), prose regex-mirrors | Not a direct agent-emitted SKILL.md invocation. |
| **Residual agent-run families that STILL carry the identical untrusted-exec hole** (exhaustive — deepen review proved the first draft was non-exhaustive) | `legal-generate` (`:60`, git-root `redact-sentinel.sh` — the **secret-redaction gate**), `trigger-cron` (`:40,43,47`, prod-cron POST), `incident` (owns redact-sentinel.sh), `skill-security-scan` (`:59,66`), `skill-creator` (`:213`), `kb-search`, `harvest-debt`, `seo-aeo`, `drain-labeled-backlog`, `constraint-scaffold`, `model-launch-review`, `plan` (`:327,840` archive-kb.sh), `compound-capture` (`:473` archive-kb.sh) | **Deferred to a P1 `type/security` follow-up (AC11), NOT silently.** #6121 §2 enumerates only the in-scope files; these are genuinely-distinct families whose migration would unbounded this PR. The PR body states the surface **remains open** for them; each is inline-triaged in the follow-up (`wg-defer-only-after-inline-triage`). **Deliberate scope call** — recorded as a User-Challenge in `decision-challenges.md` (the operator's stated 14-family scope is the default; reviewers pushed to fold all in). Only the zero-marginal-cost cross-caller case (`product-roadmap`) was folded in. |

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Confirm `EXACT_LITERAL_SAFE_COMMANDS` already contains `${WORKTREE_MANAGER_DEPLOYED_FORM} list` and `${WORKTREE_MANAGER_DEPLOYED_FORM} ls` (Slice B). `grep -n 'WORKTREE_MANAGER_DEPLOYED_FORM' apps/web-platform/server/safe-bash.ts`.
- Confirm both factories inject `CLAUDE_PLUGIN_ROOT` (server-correct invariant): `git grep -n 'pluginPath: trustedPluginPath\|pluginPath,' apps/web-platform/server/{agent-runner-query-options,cc-dispatcher}.ts` (the loaded-gun guard comment confirms both source `getPluginPath()`).
- Re-run the **broad** site enumeration and freeze the per-site migrate/exclude list: `git grep -nE 'plugins/soleur/skills/[^ ]+\.sh' -- <14 in-scope files> | grep -vE '\.test\.sh'`. Classify each hit against the §Scope decision rule.

### Phase 1 — Migrate agent-run invocations (per-site fallback discipline)
Rewrite each in-scope site's `[./|../../|$(git rev-parse --show-toplevel)/]plugins/soleur/<path>` prefix to
`${CLAUDE_PLUGIN_ROOT:-<preserved-local-fallback>}/<path>`, where **`<preserved-local-fallback>` = the site's
existing anchor** so the CLI (unset) path still resolves from that site's CWD:
- Repo-root CWD → `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` (default; matches Slice B).
- From inside `.worktrees/feat-<name>` (e.g. brainstorm:37 draft-pr) → `${CLAUDE_PLUGIN_ROOT:-../../plugins/soleur}`.
- Git-root-anchored (compound:289) → `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`.
- No-`bash`/env-prefixed direct exec (brainstorm:344 `SOLEUR_…= ./plugins/…`) → keep the env prefix, swap the path anchor identically.

### Phase 2 — safe-bash confirmation (expected: no code change)
- Run the new coupling test (Phase 3). If it passes with the existing 2 entries, `safe-bash.ts` is untouched.
- If any migrated `list`/`ls` emission is NOT a member (e.g. a `list` site whose fallback anchor differs, producing a distinct literal), **only then** add that exact deployed-form literal to `EXACT_LITERAL_SAFE_COMMANDS` (exact-equality carve-out, Stage 0 BEFORE the `$`-denylist — do NOT weaken `SHELL_METACHAR_DENYLIST`). Route any such edit through **security-sentinel**.

### Phase 3 — AC5↔AC6 coupling test (the primary new code)
Add `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts` (vitest node project — matches
`include: ["test/**/*.test.ts"]`; imports `EXACT_LITERAL_SAFE_COMMANDS` from `../server/safe-bash`):
1. **Directory-walk** `plugins/soleur/skills/**/*.md` (walk, not a hardcoded file list — drift-guard Sharp Edge) from repo root.
2. For each line, extract every command matching the read-only-verb deployed form. Scope the regex to the ONLY read-only verb family in scope (YAGNI — deepen simplicity+security): `bash \$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}/skills/git-worktree/scripts/worktree-manager\.sh (list|ls)\b`. (Do NOT add a speculative "any other read-only verb" clause — extend only when a second verb actually appears.)
3. Assert **each extracted exact command string ∈ `EXACT_LITERAL_SAFE_COMMANDS`** — so a future edit that emits a `list`/`ls` in a form NOT carved out fails loudly (instead of silently degrading to the review gate — the AC5↔AC6 coupling the advisor flagged).
4. **Vacuity guard:** assert the walk found **≥ 1** emission (a broken walk / regex yields zero → red). Do NOT hardcode `≥4` (today's exact git-worktree count) — that false-fails when a `list` site is legitimately removed (deepen simplicity + security P2). Document the current count (4) in a comment. Route the guard where the drift surface lives (learnings #4: avoid vacuity).

### Phase 4 — ADR-093 amendment + C4 check (Architecture Decision deliverable)
- Amend `ADR-093-…md` `## Consequences`: the "Negative/accepted … still CWD-relative … until Slice B lands" caveat is now resolved for the in-scope families by this slice; record the residual out-of-scope families + the follow-up issue. No new ADR.
- C4: **no impact** (see §Architecture Decision — enumeration cited).

## Files to Edit
- `plugins/soleur/skills/git-worktree/SKILL.md` (22 sites)
- `plugins/soleur/skills/ship/SKILL.md` (4 sites; exclude :605)
- `plugins/soleur/skills/brainstorm/SKILL.md` (6 sites)
- `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` (2–3 sites)
- `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` (1 site)
- `plugins/soleur/skills/merge-pr/SKILL.md` (1 site)
- `plugins/soleur/skills/drain-prs/SKILL.md` (2 sites)
- `plugins/soleur/skills/fix-issue/SKILL.md` (1 site)
- `plugins/soleur/skills/archive-kb/SKILL.md` (3 sites)
- `plugins/soleur/skills/deploy/SKILL.md` (1 site)
- `plugins/soleur/skills/pencil-setup/SKILL.md` (3–5 sites)
- `plugins/soleur/skills/feature-video/SKILL.md` (2 sites)
- `plugins/soleur/skills/community/SKILL.md` (2 sites; exclude :75–78)
- `plugins/soleur/skills/compound/SKILL.md` (2 sites)
- `plugins/soleur/skills/product-roadmap/SKILL.md` (2 sites — :29,39, folded in: same `roadmap-reconcile.sh` as migrated brainstorm:119)
- `knowledge-base/engineering/architecture/decisions/ADR-093-…md` (amend Consequences)
- `apps/web-platform/server/safe-bash.ts` — **only if** Phase 2 surfaces a new list/ls literal (expected: untouched)

## Files to Create
- `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts` (AC5↔AC6 drift-coupling test)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 (migration completeness — BROAD pattern; deepen-plan security + spec-flow P1 fix):** the narrow `bash [^ ]*\./?…` grep is a **false-passing gate** — it cannot match `bash plugins/…` (no-dot), no-`bash`, `../../`, or `$(git rev-parse…)` forms (the exact undercount class this slice exists to close). Use the **broad Phase-0 pattern**: `git grep -nE 'plugins/soleur/skills/[^ ]+\.sh' -- <in-scope files> | grep -vE 'CLAUDE_PLUGIN_ROOT' | grep -vE '\.test\.sh'` returns **0** lines after removing the explicitly-classified prose/operator-echo sites (ship:605, community:75–78). Any residual non-`${CLAUDE_PLUGIN_ROOT}` hit = an un-migrated CWD-relative site = the hole still open.
- **AC2 (no over-migration + canary-neutral):** `git diff --stat` touches only the in-scope skill files + `product-roadmap/SKILL.md` (folded — see §Scope) + the ADR + the new test; the excluded operator-run families (`provision-*`, `flag-*`, …), `.test.sh` files, and any ADR-079 fixture/snapshot are **unchanged** (canary-neutral — `CLAUDE_PLUGIN_ROOT` is not in the `--setenv` allowlist, so the projection is byte-identical by construction).
- **AC3 (per-site fallback correctness):** every migrated site's fallback is CLI-correct for its CWD anchor — repo-root sites use `./plugins/soleur`, worktree-internal sites use `../../plugins/soleur`, git-root sites use `$(git rev-parse --show-toplevel)/plugins/soleur`. **Fallback exactness is security-load-bearing ONLY for the `list`/`ls` sites** (their emitted literal must equal an `EXACT_LITERAL_SAFE_COMMANDS` member); for write/read-non-list-verb sites a wrong anchor is a CLI-only resolution bug, not a security one. Spot-verify: `git grep -n 'CLAUDE_PLUGIN_ROOT:-\.\./\.\./' brainstorm/SKILL.md` and `…:-\$(git rev-parse` in compound + legal-generate each return ≥1.
- **AC5↔AC6 (coupling test, the advisor requirement):** `plugin-root-list-carveout-coupling.test.ts` passes: every `list`/`ls` command emitted by a migrated skill via the `${CLAUDE_PLUGIN_ROOT}` form **is a member of `EXACT_LITERAL_SAFE_COMMANDS`**, with a `≥1` vacuity floor (current inventory = 4 git-worktree `list` sites; `≥1` avoids a false-fail when a `list` site is legitimately removed — the magic `≥4` was a brittle knob per deepen simplicity+security review).
- **AC7 (safe-bash unweakened):** `SHELL_METACHAR_DENYLIST` and `PATH_TRAVERSAL_DENYLIST` are unchanged; the existing `safe-bash.test.ts` deny-matrix (injection tails, different var, traversal, `$(…)`, different script) still passes green.
- **AC9 (green suites):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; full web-platform vitest green (incl. the new coupling test + `safe-bash.test.ts`); `bash scripts/test-all.sh` scripts/bun shards green; `bun test plugins/soleur/test/components.test.ts` green (no description-budget regression — invocation-line edits don't touch `description:` frontmatter).
- **AC10 (ADR):** ADR-093 Consequences amended (broader migration recorded + exhaustive residual families named). No new ADR. (C4 has no impact — prose note in §Architecture Decision, not an AC.)
- **AC11 (residual untrusted-exec surface — honestly framed as OPEN; P1 security follow-up):** a follow-up issue (labelled `type/security`, `priority/p1-high`) enumerates the **exhaustive** residual agent-run families that STILL carry the identical untrusted-code-execution hole after this PR. The deepen-plan reviewers proved the first-draft list was non-exhaustive; the issue MUST include `legal-generate` (`:60`, git-root `redact-sentinel.sh` — the **secret-redaction gate**, elevated stakes), `trigger-cron` (`:40,43,47`, prod-cron POST), `incident`, `skill-security-scan` (`:59,66`), `skill-creator` (`:213`), `kb-search`, `harvest-debt`, `seo-aeo`, `drain-labeled-backlog`, `constraint-scaffold`, `model-launch-review`, `plan` (`:327,840`), `compound-capture` (`:473`). The PR body states plainly the surface **remains open** for these until the follow-up lands; each is inline-triaged agent-run vs operator-run in that issue (`wg-defer-only-after-inline-triage`).

**Cut as ceremony (deepen-plan simplicity review):** former AC4 (server-invariant re-statement — lives in Overview prose), AC8 (canary-neutral — folded into AC2), AC12 (`Closes #6121` — PR mechanics, in §Sequencing) were LARP ACs restating already-true invariants; removed so every AC is a real post-condition gate.

## Domain Review

**Domains relevant:** Engineering (security).

### Engineering / Security
**Status:** reviewed (plan-time classification + learnings research; deepen-plan security triad + review-time security-sentinel/user-impact-reviewer to follow)
**Assessment:** `type/security` change closing an untrusted-code-execution surface. The security design is fully determined by Slice B's established pattern (exact-literal carve-out already present; both factories inject the env var). Residual risk is **scope-completeness** (a missed site leaves the hole) and **coupling-test vacuity** — both addressed by the broad-grep classification rule + the walk/vacuity-guard test. `safe-bash.ts` is expected untouched; security-sentinel confirms carve-out completeness and no denylist weakening at implement/review time.

### Product/UX Gate
Not applicable — no `components/**`, `app/**/page.tsx`, or user-facing UI surface. Product = NONE.

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-093** (`SDK plugin source is platform-deployed, not connected-repo`). This slice resolves the
ADR's recorded "Negative/accepted" caveat (shelled-out `bash ./plugins/…` still CWD-relative until the
broader migration lands) for the in-scope families. Amendment records: broader-migration slice landed, the
drift-coupling test, and the residual out-of-scope families + follow-up issue. **No new ADR** (this implements
an already-recorded decision).

### C4 views
**No C4 impact.** Read of `model.c4` / `views.c4` / `spec.c4`: the relevant elements already exist —
`platform.plugin` (container) and the `connectedRepoPlugin` external element (referenced in `views.c4:37`,
added by Slice A / ADR-093) already model the deployed-plugin vs untrusted-connected-repo-copy boundary. This
slice changes only the **shell-invocation convention** *within* those existing elements; it introduces **no new
external human actor, no new external system/vendor, no new container/data-store, and no changed
actor↔surface access relationship**. (Checked all three actor/system/relationship classes against the model —
none require an edit; "None" is supported, not asserted.)

### Sequencing
Not sequenced — the migration is complete and true at merge (both factories already inject the env var in prod).

## Observability

This is a docs (SKILL.md) + test change with no new server/infra runtime surface, so the heavy observability
schema is not required. The **drift signal** is the CI coupling test (`plugin-root-list-carveout-coupling.test.ts`)
+ the existing in-image `plugin-root-propagation` gate (Slice B): a future edit that reintroduces a
CWD-relative `list`/`ls` emission, or breaks env propagation, reddens CI (fail-closed, no SSH needed).

```yaml
liveness_signal:    { what: "coupling + propagation CI tests", cadence: "every PR/CI run", alert_target: "CI red on PR", configured_in: "vitest + plugin-root-propagation-gate" }
error_reporting:    { destination: "CI job failure", fail_loud: true }
failure_modes:      [ { mode: "migrated list/ls form drifts out of carve-out", detection: "coupling test asserts membership", alert_route: "CI red" }, { mode: "walk/regex breaks so zero matches", detection: "vacuity guard (>=4)", alert_route: "CI red" } ]
logs:               { where: "CI job logs", retention: "CI default" }
discoverability_test: { command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-list-carveout-coupling.test.ts", expected_output: "PASS, >=4 list emissions scanned, all members" }
```

## Open Code-Review Overlap

None beyond #6121 itself (the work-target). The residual non-enumerated families are handled via a fresh
follow-up issue (AC11), not an existing scope-out.

## Test Strategy
- **New:** `plugin-root-list-carveout-coupling.test.ts` (vitest node) — the AC5↔AC6 drift guard.
- **Regression:** existing `safe-bash.test.ts` (deny-matrix + carve-out) must stay green unchanged.
- **Suites:** `tsc --noEmit` (in-package form), full web-platform vitest, `bash scripts/test-all.sh` shards, `bun test plugins/soleur/test/components.test.ts`.
- **Runner discipline:** typecheck = `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`); coupling test path lives under `test/**/*.test.ts` to match the vitest node include glob (NOT co-located).

## Risks & Sharp Edges
- **Per-site fallback anchor is load-bearing.** The fallback must match the site's CWD anchor (`.`, `../../`, or `$(git rev-parse --show-toplevel)/plugins/soleur`). A blanket `./plugins/soleur` on the worktree-internal or git-root sites breaks the CLI (unset) path. Enumerated in Phase 1; AC3 verifies.
- **Narrow grep undercounts.** Always use the broad `plugins/soleur/skills/[^ ]+\.sh` pattern; the `bash `-anchored form misses env-prefixed / no-`bash` / `../../` / `$(…)` execs. Classify each hit (agent-exec vs prose vs operator-echo) — do not migrate prose (ship:605) or credential-setup echoes (community:75–78).
- **`git grep … -- <pathspecs>` ordering** (learnings #6): every positional path AFTER `--`, or it's parsed as a revision.
- **Coupling-test vacuity** (learnings #4): the walk must be a directory walk with a ≥4 sanity floor; a hardcoded file list or a zero-match regex false-passes. Route the guard to the drift surface (SKILL.md emissions ↔ TS Set).
- **safe-bash likely needs no edit** — resist adding entries reflexively; only a genuinely new `list`/`ls` literal (distinct fallback anchor) warrants a carve-out addition, and only via security-sentinel.
- **A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will fail `deepen-plan` Phase 4.6.** (Filled above; threshold = single-user incident.)

## Sequencing / Merge
Single atomic PR. `Closes #6121`. security-sentinel + user-impact-reviewer at review-time; deepen-plan security
triad before ship. Version bumping happens in CI (not in this feature branch).
