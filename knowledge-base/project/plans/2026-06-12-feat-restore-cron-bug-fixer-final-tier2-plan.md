---
title: "Restore cron-bug-fixer — the FINAL Tier-2-deferred cron (#5199)"
type: feat
status: planned
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
issue: 5199
branch: feat-one-shot-restore-cron-bug-fixer-5199
---

# Restore cron-bug-fixer — the FINAL Tier-2-deferred cron (#5199) ✨

## Overview

`cron-bug-fixer` is the **last** cron in `TIER2_DEFERRED_CRONS`. The 7
`mergeMode:"auto"` PR-flow crons were restored in PR 5235 (merged, deployed
`web-v0.125.0`); `cron-ux-audit` was restored earlier (PR 5202). After this PR,
`TIER2_DEFERRED_CRONS` is **EMPTY** and the Tier-2 boundary is fully retired.
This **closes #5199** (use `Closes #5199` in the PR body).

bug-fixer is special and carries the highest blast radius of any restored cron:
it autonomously **writes code** and opens `bot-fix/*` PRs (default
`mergeMode: auto`), running `claude --print` against the **live prod repo** with
a write-capable GitHub-App token. A containment regression here is a
**single-user-incident-class** brand-survival event — strictly higher than the
read/issue crons because it **mutates source**.

It was kept deferred for ONE specific reason: its `bot-fix/*` head pattern is
**outside** the stale-bot-PR watchdog's daily age-scan. The watchdog
(`cron-cloud-task-heartbeat.ts`, added by PR 5200 / issue #5138) only scans
`ci/*` and `self-healing/auto-*` heads for PRs whose `enablePullRequestAutoMerge`
silently disarmed on a merge conflict. A stale bug-fixer PR on a `bot-fix/*`
branch would rot invisibly. **This PR closes that gap FIRST (atomic — no
restore-without-watchdog window) and only then un-defers the cron.**

This is the third application of the validated Tier-2-restore recipe
(PR 5202 cron-ux-audit; PR 5235 the 7 auto-crons). The deltas unique to
bug-fixer are spelled out in the Research Reconciliation table below — the most
important is that **bug-fixer's commit step lives in the `fix-issue` SKILL, not
in `safeCommitAndPr`**, so its bash allowlist legitimately carries `git`/`gh pr`
persistence verbs (the 7 auto-crons did NOT — they persist node-side).

## User-Brand Impact

**If this lands broken, the user experiences:** a daily autonomous agent that
either (a) silently produces nothing because the containment hook denies a verb
its prompt emits (green monitor, zero `bot-fix/*` PRs — the silent-no-op class),
or (b) opens malformed/uncontained PRs against the live auto-deploying repo. The
worst concrete artifact is a `bot-fix/*` PR that auto-merges to `main` and ships
to prod via the `web-platform-release.yml` path-filtered deploy.

**If this leaks, the user's workflow/money is exposed via:** the spawned
`claude --print` carries `ANTHROPIC_API_KEY` (billing abuse if exfiltrated) and a
GitHub-App `GH_TOKEN` (push + PR primitive on the public auto-deploying repo). A
prompt-injected GitHub-issue body steering the model to exfiltrate either secret
is the threat the containment hook exists to sever. Narrowing the token mint to
`DEFAULT_CRON_TOKEN_PERMISSIONS` + `repositories: [REPO_NAME]` bounds a leaked
token to a single-user incident (contents/issues/pull_requests:write on soleur
only — cannot dispatch workflows, edit rulesets, or write check-runs).

**Brand-survival threshold:** single-user incident.

> **CPO sign-off required at plan time before `/work` begins.** Invoke the CPO
> domain leader, or confirm CPO has reviewed (carry-forward from the #5046/#5199
> Tier-2 framing). `user-impact-reviewer` runs at review-time (review/SKILL.md
> conditional-agent block).

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description / prior PRs) | Reality (ground-truthed this session) | Plan response |
| --- | --- | --- |
| "Restore is the same recipe as the 7 auto-crons (PR 5235)" | **Mostly** — but bug-fixer's commit step is in the `fix-issue` SKILL, NOT `safeCommitAndPr`. `cron-safe-commit-parity.test.ts:69` keeps it in `EXEMPT` ("fix-issue skill owns the commit step"). | bug-fixer's `CRON_BASH_ALLOWLISTS` entry legitimately INCLUDES `git`/`gh pr create`/`gh pr edit` persistence verbs (unlike the 7 auto-crons whose allowlists EXCLUDE them — parity invariant 3). It stays in `EXEMPT`, NOT `MIGRATED_PROMPT`. |
| "Add a CRON_BASH_ALLOWLISTS entry mirroring the 7 auto-crons' shape" | The 7 auto-crons are issue-creator-only. bug-fixer's bash surface (from `fix-issue/SKILL.md`) is **much wider**: `gh issue view/comment/edit`, `gh pr create/edit`, `git add -- <path>`, `git commit -m`, `git push -u origin`, `git status`, `git worktree`, `git branch -D`, `bash …/worktree-manager.sh`, plus a test-runner invocation. | Enumerate the ACTUAL verbs (see Phase 3 §"Enumerated allowlist"). Mirror `cron-roadmap-review`'s SHAPE (the widest existing Tier-1 allowlist, which already carries git verbs), NOT the issue-creator shape. |
| "The prompt emits commands the hook will allow" | The `fix-issue` SKILL emits **three hook-DENIED constructs**: `eval "$TEST_CMD"` (`$VAR` indirection + the `eval` verb), `node -e "…"` test detection, and `… 2>&1 \| tail -50` (pipe + redirect). The `gh pr create --body "$(cat <<'EOF'…)"` form is `$(...)` substitution → DENIED. | **The prompt MUST be rewritten to emit LITERAL allowlisted forms** (this is the central work item — see Phase 3.5). The cron passes its OWN prompt (`fixIssuePrompt`) which invokes `/soleur:fix-issue`; the SKILL's bash patterns are what the model emits. The containment break in PR 5235's community-monitor was exactly this `$VAR`/`$(...)` class. |
| "bug-fixer's non-GitHub egress targets need allowlist entries" | bug-fixer dials `api.anthropic.com` (claude eval) + `api.resend.com` (notify-ops-email) + `github.com`/`api.github.com` (clone/push/gh). **ALL FOUR are already in `cron-egress-allowlist.txt`.** | **No egress-allowlist edit needed** (verified). Note this explicitly in the plan; do NOT broaden. |
| "Narrow the token mint" | bug-fixer currently mints with **NO permissions** (full installation grant) at `cron-bug-fixer.ts:636`: `mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS })`. | Add `permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME]` (both already importable from `_cron-shared` — `DEFAULT_CRON_TOKEN_PERMISSIONS` is exported at `_cron-shared.ts:131`; `REPO_NAME` at `:11`). |
| "Extend the watchdog scan to bot-fix/*" | `BOT_PR_HEAD_PREFIXES = ["ci/", "self-healing/auto-"]` at `cron-cloud-task-heartbeat.ts:90`. `scheduledLabelFromHead` (`:120`) only reverse-derives labels for `ci/` heads; `isStaleBotPr` (`:135`) gates on `BOT_PR_HEAD_PREFIXES`. | Add `"bot-fix/"` to `BOT_PR_HEAD_PREFIXES`. `bot-fix/<N>-<slug>` heads have no `scheduled-<cron>` label (bug-fixer files no scheduled issue), so they correctly route to **Sentry-only** via the existing `scheduledLabel === null` path (`:460` `if (!pr.scheduledLabel) continue`). No change to `scheduledLabelFromHead` needed — its `ci/`-only return is correct. |
| "issue #5199 already resolved?" | `gh issue view 5199` → **OPEN** (title: "infra: restore the 9 crons still deferred after Tier-2 boundary"). | Premise holds. `Closes #5199` is correct — this is the last cron. |

**Premise Validation note:** Checked #5199 (OPEN — correct to close). PR 5235 / PR
5200 `gh` lookups failed in-sandbox (network), but the substrate code carries
both their landed comments verbatim (`_cron-shared.ts:344-354` for the 7-cron
restore; `cron-cloud-task-heartbeat.ts:79-91` for the #5138 watchdog), so both
are confirmed merged. The token-mint, watchdog-prefix, egress, and parity-test
artifacts were all read directly this session — no paraphrase-from-memory.

## Acceptance Criteria

### Pre-merge (PR)

**Watchdog prerequisite (lands in THIS PR — atomic):**

- [x] **AC1** `BOT_PR_HEAD_PREFIXES` in `cron-cloud-task-heartbeat.ts` includes
  `"bot-fix/"` (alongside `"ci/"` and `"self-healing/auto-"`).
- [x] **AC2** `cron-cloud-task-heartbeat.test.ts` asserts `BOT_PR_HEAD_PREFIXES`
  contains `"bot-fix/"` AND that a `bot-fix/<N>-<slug>` PR older than 48h is
  classified stale by `isStaleBotPr` (and routes Sentry-only because
  `scheduledLabelFromHead` returns `null` for a non-`ci/` head).

**Restore:**

- [x] **AC3** `"cron-bug-fixer"` removed from `TIER2_DEFERRED_CRONS`
  (`_cron-shared.ts`); the set is now `new Set([])` (EMPTY). The block comment
  (`:320-354`) is rewritten: no crons remain deferred; the Tier-2 boundary is
  fully restored.
- [x] **AC4** A finite, per-construct, evidence-gated `cron-bug-fixer` entry
  added to `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts`). Contains
  NO entry beginning with `gh api` (F4a). Enumerated verbs only (Phase 3).
- [x] **AC5** `cron-bug-fixer.ts` token mint narrowed to
  `mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS, permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] })`.
  `DEFAULT_CRON_TOKEN_PERMISSIONS` imported from `_cron-shared` (`REPO_NAME`
  already imported). Does NOT use `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`
  (contents:read would 403 the push).
- [x] **AC6** The defensive `deferIfTier2Cron` guard at
  `cron-bug-fixer.ts:586-595` is KEPT (becomes a no-op once out of the set —
  mirrors the 7 restored crons + cron-ux-audit).
- [x] **AC7** `cron-egress-allowlist.txt` UNCHANGED — bug-fixer's non-GitHub
  egress targets (`api.anthropic.com`, `api.resend.com`) are already present;
  no broadening. (Verification: `grep -E 'api.anthropic.com|api.resend.com' apps/web-platform/infra/cron-egress-allowlist.txt` returns both.)
- [x] **AC8** The `fix-issue` prompt path emits **LITERAL allowlisted command
  forms** — no `$VAR` indirection, no `NAME=` assignment-prefix, no `$(...)`, no
  pipes/redirects in the hook-gated bash. Specifically the `eval "$TEST_CMD"` /
  `node -e` / `… | tail -50` / `$(cat <<EOF)` constructs in
  `fix-issue/SKILL.md` are replaced with literal forms (Phase 3.5).
- [x] **AC9 (FAILING-FIRST, parity)** In `cron-safe-commit-parity.test.ts`:
  `cron-bug-fixer` IS a `CRON_BASH_ALLOWLISTS` key AND ABSENT from
  `TIER2_DEFERRED_CRONS`; AND `[...TIER2_DEFERRED_CRONS]` deep-equals `[]`
  (EMPTY). The existing `only cron-bug-fixer remains Tier-2-deferred` test
  (`:246-248`) is rewritten to assert emptiness.
- [x] **AC10 (FAILING-FIRST, token)** A test asserts `cron-bug-fixer.ts` source
  contains `permissions: DEFAULT_CRON_TOKEN_PERMISSIONS` and
  `repositories: [REPO_NAME]`.
- [x] **AC11 (FAILING-FIRST, decide-paired)** In
  `cron-claude-eval-substrate.test.ts`: feed bug-fixer's REAL prompt command
  forms through the pure `decide(cmd, CRON_BASH_ALLOWLISTS["cron-bug-fixer"])`
  and assert **ALLOW** for the enumerated `git`/`gh`/test verbs (literal forms),
  and assert **DENY** for: `gh api repos/jikig-ai/soleur/issues`, `$(...)`
  substitution, pipes, redirects, `NAME=` env-assignment-prefix, and
  `cat /proc/self/environ`. (A membership/parity test alone is vacuous-green
  against a runtime DENY — the `$ROUTER`-class trap from PR 5235.)
- [x] **AC12 (FAILING-FIRST, watchdog)** AC2's test from the watchdog prereq.
- [x] **AC12b (REQUIRED, surfaced at deepen)** `cron-bug-fixer.test.ts`'s
  `execFileSyncSpy` mock (`:35-46`) is widened to return `allow` for
  `tool_name === "Bash"`. **Why:** today the mock returns `deny` for everything
  except Task/Agent/Skill, on the assumption "cron-bug-fixer has no Bash
  allowlist → the first-verb allow branch is skipped" (`:33-34`). Once bug-fixer
  GAINS a `CRON_BASH_ALLOWLISTS` entry, `runHookSelfTest`'s `allow[0]` probe
  fires (`_cron-claude-eval-substrate.ts:379-389`) and the current mock denies
  it → throws "verb not allowed" → EVERY handler test in the file fails. Add
  `payload.tool_name === "Bash"` to the `allowed` condition and update the
  comment (the handler unit tests cover spawn/issue-selection, NOT hook
  containment — that is AC11's job in the substrate test).
- [x] **AC13** Runbook `cloud-scheduled-tasks.md` updated: bug-fixer moved to
  **Tier-1**; the Tier-2 section states **all Tier-2 crons are restored /
  `TIER2_DEFERRED_CRONS` is empty**; the "Extending scan to bot-fix/* is OUT OF
  SCOPE" caveat (`:683-684`) is removed (it's now IN scope and done).
- [x] **AC14** `tsc --noEmit` clean (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`).
- [x] **AC15** Targeted vitest suites green (Phase "Test Strategy" command list).
- [ ] **AC16** PR body uses `Closes #5199`.

### Post-merge (operator-discretion, NOT auto-fired)

- [ ] **AC17 (OPTIONAL)** `/soleur:trigger-cron bug-fixer.manual-trigger` with
  data `{ issue_number: <a real open low-risk issue> }` over the full
  containment path. **Note: this OPENS A PR and spends budget**, so it is NOT
  auto-fired. The `scheduled-bug-fixer` Sentry monitor is the standing
  regression net. Automation feasibility: feasible via the trigger-cron route,
  but deliberately operator-gated because it mutates the live repo + spends
  Anthropic budget (subjective go/no-go = human judgment).

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

- Confirm `DEFAULT_CRON_TOKEN_PERMISSIONS` is exported from `_cron-shared.ts`
  (`:131`) and `REPO_NAME` (`:11`) — both confirmed this session.
- Confirm bug-fixer's egress is already covered:
  `grep -E 'api.anthropic.com|api.resend.com|github.com|api.github.com' apps/web-platform/infra/cron-egress-allowlist.txt`
  → all four present.
- Re-read `fix-issue/SKILL.md` Phases 1–6 and enumerate EVERY bash verb (done in
  this plan; re-verify at /work in case the SKILL drifted).
- Read the vitest `include:` globs (`apps/web-platform/vitest.config.ts`) to
  confirm test file paths land on a collected project before writing them
  (Sharp Edge — co-located component tests are silently skipped).
- Test runner is **vitest** (`./node_modules/.bin/vitest run <path>`), NOT
  `bun test` (bunfig.toml `pathIgnorePatterns`). Typecheck is the in-package
  `tsc`, NOT `npm run -w`.

### Phase 1 — RED: watchdog prerequisite (write the failing test, then fix)

1. Add to `cron-cloud-task-heartbeat.test.ts` (AC2/AC12): assert
   `BOT_PR_HEAD_PREFIXES` contains `"bot-fix/"`; assert `isStaleBotPr` returns
   `true` for `{ head: { ref: "bot-fix/4321-foo" }, created_at: <49h ago>, draft: false, labels: [] }`; assert `scheduledLabelFromHead("bot-fix/4321-foo")` is `null` (Sentry-only routing).
2. GREEN: in `cron-cloud-task-heartbeat.ts`, add `"bot-fix/"` to
   `BOT_PR_HEAD_PREFIXES` (`:90`). Update the const's comment to note `bot-fix/*`
   is now covered (bug-fixer restore, #5199). Update the `STALE_BOT_PR_THRESHOLD`
   block comment (`:79-88`) — it currently says the scan covers `ci/*` cohorts;
   add `bot-fix/*` (autonomous fixer PRs whose auto-merge disarms on conflict).
   **Do NOT touch** `scheduledLabelFromHead` — its `ci/`-only return is correct;
   `bot-fix/*` PRs have no scheduled-issue label and must route Sentry-only via
   the existing `!pr.scheduledLabel` guard.

### Phase 2 — RED: parity + token tests (write failing, before code)

1. In `cron-safe-commit-parity.test.ts`:
   - Add a `RESTORED_BUG_FIXER` block (or extend the existing #5199 describe):
     `cron-bug-fixer` IS a `CRON_BASH_ALLOWLISTS` key AND ABSENT from
     `TIER2_DEFERRED_CRONS` (AC9).
   - Rewrite the `only cron-bug-fixer remains Tier-2-deferred` test (`:246-248`)
     to: `expect([...TIER2_DEFERRED_CRONS]).toEqual([])` (EMPTY).
   - Add a token test (AC10): `cron-bug-fixer.ts` source contains
     `permissions: DEFAULT_CRON_TOKEN_PERMISSIONS` + `repositories: [REPO_NAME]`,
     and does NOT contain `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`.
   - Keep `cron-bug-fixer.ts` in `EXEMPT` (it does NOT route through
     `safeCommitAndPr` — the SKILL owns the commit). Update the `EXEMPT` rationale
     string only if wording drifts; the existing one (`:69`) is correct.
   - **Verify invariant-3 does NOT apply to bug-fixer:** invariant 3 iterates
     `MIGRATED_ALL`; bug-fixer is in `EXEMPT`, so its allowlist's `git`/`gh pr`
     verbs are NOT subject to the persistence-exclusion assert. Confirm bug-fixer
     is NOT accidentally added to `MIGRATED_PROMPT`/`MIGRATED_HANDLER` (that would
     red invariant 4's `EXEMPT`-disjoint check).
3. **Widen the `cron-bug-fixer.test.ts` mock (AC12b — RED→GREEN coupling).** In
   the SAME RED batch, edit `execFileSyncSpy` (`:35-46`) to add
   `payload.tool_name === "Bash"` to the `allowed` condition (and update the
   `:33-34` comment). This is GREEN-coupled to Phase 3 (adding the allowlist
   entry): the allowlist makes `runHookSelfTest` run the `allow[0]` Bash probe,
   which the un-widened mock denies → the whole file reds. Land the mock widen in
   the same commit as the allowlist add so no intermediate commit is red.

### Phase 3 — RED→GREEN: the `CRON_BASH_ALLOWLISTS` entry + decide-paired test

**Enumerated allowlist for `cron-bug-fixer`** (each verb evidence-gated to a
`fix-issue/SKILL.md` phase; sub-command granularity; LITERAL forms only):

**This list is EVIDENCE-GATED to the EXACT verbs `fix-issue/SKILL.md` emits**
(re-verified at deepen — `grep -noE 'gh (issue|pr) [a-z]+|git [a-z-]+|bash …worktree-manager\.sh' SKILL.md`).
Speculative "sibling of roadmap-review" verbs (`git switch`, `git rev-parse`,
`gh label list/create`, `gh issue list/create/close`, `gh pr list/comment`) are
**NOT emitted by the SKILL and are REMOVED** (labels are precreated node-side via
`precreateLabels`/octokit at `cron-bug-fixer.ts:540`, NOT bash). The finite,
minimal set:

```text
gh issue view          # SKILL Phase 1 (:81): gh issue view <N> --json …
gh issue comment       # SKILL Phase 6 (:220): gh issue comment <N> --body …
gh issue edit          # SKILL Phase 6 (:232): gh issue edit <N> --add-label …
gh pr create           # SKILL Phase 5 (:168/:209): gh pr create --title … --body-file …
gh pr edit             # SKILL Phase 5.5 (:200/:206): gh pr edit <N> --add-label …
git status             # SKILL Phase 5 (:157): git status --porcelain
git add                # SKILL Phase 5 (:160): git add -- <path> (blanket forms hook-denied)
git commit             # SKILL Phase 5 (:161): git commit -m …
git checkout           # SKILL Phase 3 (:127): git checkout (worktree fallback path)
git worktree           # SKILL Phase 3 (:133/:239): git worktree add … / remove …
git branch             # SKILL Phase 6 (:240): git branch -D …
git push               # SKILL Phase 5 (:162): git push -u origin … (origin-only enforced by gitVerbReason)
bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh   # SKILL Phase 3 (:130)
./node_modules/.bin/vitest run   # SKILL Phase 2/4 test verify — LITERAL form (Phase 3.5 rewrite replaces eval "$TEST_CMD")
```

> **`allow[0]` safety (runHookSelfTest):** the FIRST entry is `gh issue view` —
> a bare prefix that `decide()` allows as a literal (verified: tokenizes to
> `["gh","issue","view"]`, no metachar/git-verb/arg-injection trip). The spawn-time
> `runHookSelfTest` runs `allow[0]` through the real hook and REQUIRES allow; a
> first entry that needs args or trips a guard would abort every run. Mirror the
> siblings' convention (all use a bare no-arg verb as `allow[0]`).
>
> **`git fetch` note:** the SKILL's `worktree-manager.sh` runs `git fetch`
> INTERNALLY (its own child process, gated by the egress firewall — same posture
> as `community-router.sh`'s child `curl`/`gh`), NOT as a direct prompt verb. So
> `git fetch` is NOT allowlisted here; the `bash …worktree-manager.sh` entry
> covers the script invocation.

**EXCLUDED (do NOT add):**
- `gh api` — F4a (arbitrary-method API access defeats the exfil defense).
- `gh pr merge` — bug-fixer arms auto-merge via the node-side
  `enableAutoMergeSquash` GraphQL mutation (`runAutoMergeGate`), NOT a prompt
  `gh pr merge`. Keep it out (parity invariant 3's PERSISTENCE_PREFIXES list
  names `gh pr merge` as a forbidden form).
- `eval`, `node -e`, raw `curl`/`wget` — interpreters/egress, hook-denied
  regardless; the prompt must not emit them (Phase 3.5).

> **Note on `git config`/`git remote`/`git ls-remote`:** these are
> unconditionally denied by `gitVerbReason` (they reveal/redirect the
> token-bearing remote URL) — do NOT allowlist; the SKILL must not emit them.

1. RED: write the decide-paired test in `cron-claude-eval-substrate.test.ts`
   (mirror the existing `RESTORED` block at `:198-271`):
   - ALLOW (literal prompt forms): `gh issue view 4321 --json state,title,body,labels`;
     `gh pr create --title "[bot-fix] x" --body "summary"`;
     `gh pr edit 99 --add-label bot-fix/auto-merge-eligible`;
     `git add -- src/foo.ts test/foo.test.ts`; `git commit -m "[bot-fix] Fix #4321"`;
     `git push -u origin bot-fix/4321-foo`; `git status --porcelain`;
     `git checkout -b bot-fix/4321-foo origin/main`;
     `git worktree add .worktrees/bot-fix-4321-foo -b bot-fix/4321-foo origin/main`;
     `git branch -D bot-fix-4321-foo`;
     `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create bot-fix-4321-foo`;
     `./node_modules/.bin/vitest run` (the literal test verb, Phase 3.5).
   - DENY: `gh api repos/jikig-ai/soleur/issues`; `git add -A`; `git add .`;
     `git commit -a -m x`; `git push -u evil main`; `git config --get remote.origin.url`;
     `eval "$TEST_CMD"` (env-assignment/`$VAR`); `TEST=x npm test` (env-prefix);
     `gh issue list --search "$(cat /tmp/x)"` (`$(...)`);
     `gh issue view 1 | wc -l` (pipe); `gh issue view 1 > /tmp/x` (redirect);
     `cat /proc/self/environ`; `gh pr merge --auto`.
2. GREEN: add the `cron-bug-fixer` key to `CRON_BASH_ALLOWLISTS` with the
   enumerated verbs above and an evidence comment (which SKILL phase each verb
   comes from, the F4a/`gh pr merge` exclusions, and that persistence verbs are
   present because the SKILL — not safeCommitAndPr — owns the commit, unlike the
   7 auto-crons).

### Phase 3.5 — Rewrite `fix-issue` prompt to emit LITERAL hook-allowed forms

This is the load-bearing containment work (AC8). The `fix-issue/SKILL.md` bash
patterns are what the spawned model emits; three classes are hook-DENIED:

1. **Test detection + run** (`SKILL.md` Phase 2/4):
   - `TEST_CMD=$(node -e "…")` → DENIED (`$(...)` + `node -e` interpreter).
   - `eval "$TEST_CMD" 2>&1 | tail -50` → DENIED (`eval`, `$VAR`, pipe, redirect).
   - **Fix:** replace with a LITERAL test invocation. The repo's runner is
     `./node_modules/.bin/vitest run` (web-platform). Emit a fixed literal —
     e.g. `cd apps/web-platform && ./node_modules/.bin/vitest run` — and add the
     literal prefix to the allowlist (`cd apps/web-platform && ./node_modules/.bin/vitest run`
     splits on `&&` into two segments; `cd apps/web-platform` and
     `./node_modules/.bin/vitest run` must BOTH be allowlisted, OR use a single
     non-chained form `./node_modules/.bin/vitest run --root apps/web-platform`).
     **Decision: prefer the single-segment `--root` form** so the allowlist
     carries one literal verb (`./node_modules/.bin/vitest run`) and the prompt
     emits no `&&` chain, no `cd`, no pipe, no `2>&1`. Drop the `| tail -50`
     (the substrate already bounds + ships stdout/stderr tails).
   - **Alternative considered:** keep the dynamic `node -e`/`eval` detection but
     route it through the hook. Rejected — `node -e` and `eval` are interpreters
     the hook denies by design; the cron runs ONLY against the soleur repo where
     the runner is known, so a literal is correct and strictly safer.
2. **PR body heredoc** (`SKILL.md` Phase 5):
   - `gh pr create --body "$(cat <<'EOF' … EOF)"` → DENIED (`$(...)`).
   - **Fix:** emit `gh pr create --title … --body-file <path>` (write the body to
     a temp file in the clone with the `Write` tool — which the hook ALLOWS
     except for protected paths — then `--body-file`). **Guard the
     argument-injection rule:** `--body-file <path>` is allowed ONLY when
     `<path>` does NOT contain `@`, `..`, `/proc|/etc|/root|/home`, `.git`, or
     `.env` (`argumentInjectionReason`). A relative path inside the clone (e.g.
     `pr-body.md`) is safe. Document this in the SKILL.
3. **Scoped staging** (`SKILL.md` Phase 5) — already correct (`git add -- "$FIXED_FILE"`),
   but the prompt MUST emit explicit literal paths, not `$FIXED_FILE` indirection
   (the hook tokenizes `git add -- <path>` and the blanket-staging deny set is
   already satisfied; the `$VAR` form is fine for the SHELL but the cron prompt
   should instruct the model to substitute the real path before emitting — the
   model running `git add -- src/foo.ts` is literal, the SKILL's `$FIXED_FILE`
   is pseudocode the model fills in). **Clarify in the SKILL** that bot/cron
   invocations must emit literal paths (no shell-variable indirection) so the
   hook's tokenizer sees concrete tokens.

> **Why the prompt-rewrite is in scope:** PR 5235's community-monitor
> containment break was exactly a `$ROUTER` `$VAR` indirection that the hook
> denied at runtime while the parity test stayed green. AC11's decide-paired DENY
> assertions are the regression net; Phase 3.5 is the fix that makes the ALLOW
> assertions pass against the REAL prompt forms.

> **Scope guard:** `fix-issue` is ALSO invoked by the interactive `/soleur:go`
> path and `workflow_dispatch`, not just the cron. The literal-form rewrite must
> not regress those (a literal vitest `--root` invocation works the same
> interactively). Grep `fix-issue` invocation surfaces at /work and confirm the
> rewrite is behavior-preserving for the non-cron callers (the SKILL is the
> single source; both callers benefit from the literal form).

### Phase 4 — RED→GREEN: token mint narrowing

1. Token test already RED from Phase 2 (AC10).
2. GREEN: edit `cron-bug-fixer.ts:633-638` — add
   `permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME]` to the
   `mintInstallationToken` call; add `DEFAULT_CRON_TOKEN_PERMISSIONS` to the
   `_cron-shared` import block (`:52-60`).

### Phase 5 — Un-defer + comment rewrite

1. Remove `"cron-bug-fixer"` from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:355-357`)
   → `new Set([])`. Parity tests (Phase 2) flip green.
2. Rewrite the block comment (`:320-354`): no crons remain deferred; the Tier-2
   boundary is fully restored; #5199 closed. Note `deferIfTier2Cron` remains as a
   defensive no-op (an empty set short-circuits `has()` to false).
3. KEEP `deferIfTier2Cron` (`:359-377`) and its call site in `cron-bug-fixer.ts`
   (`:586-595`) — no-op now (AC6).

### Phase 6 — Runbook + docs

1. `cloud-scheduled-tasks.md` Tier-1/Tier-2 section (`:651-689`): move bug-fixer
   to Tier-1 (note: SKILL-mediated commit, EXEMPT from safeCommitAndPr, carries
   git/gh-pr persistence verbs). State `TIER2_DEFERRED_CRONS` is EMPTY / all
   Tier-2 crons restored. Remove the "Extending scan to bot-fix/* is OUT OF SCOPE
   for #5199" caveat (`:683-684`) — now done.
2. Update the `### Stale bot PR` watchdog prose if it enumerates the scanned
   prefixes (mention `bot-fix/*` is now scanned).

### Phase 7 — Verify

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- Run the targeted vitest suites (Test Strategy below).
- Grep guard: `grep -rn 'gh api' <new allowlist entry>` returns nothing for the
  bug-fixer key (F4a).

## Test Strategy

Write FAILING tests FIRST (cq-write-failing-tests-before). Runner: vitest
(`./node_modules/.bin/vitest run <path>` from `apps/web-platform`).

| Test file | New/edited assertions |
| --- | --- |
| `test/server/inngest/cron-cloud-task-heartbeat.test.ts` | AC2/AC12 — `bot-fix/` in `BOT_PR_HEAD_PREFIXES`; `isStaleBotPr` stale for a 49h-old `bot-fix/*` PR; `scheduledLabelFromHead` null for `bot-fix/*`. |
| `test/server/inngest/cron-safe-commit-parity.test.ts` | AC9 — bug-fixer IS allowlist key + ABSENT from deferred set; `TIER2_DEFERRED_CRONS` EMPTY (rewrite `:246-248`). AC10 — token mint literals present. Confirm bug-fixer stays in `EXEMPT`. |
| `test/server/inngest/cron-claude-eval-substrate.test.ts` | AC11 — decide-paired ALLOW (literal git/gh/test verbs) + DENY (gh api / `$(...)` / pipe / redirect / `NAME=` / `cat /proc/self/environ` / `gh pr merge`). |
| `test/server/inngest/cron-bug-fixer.test.ts` | **AC12b** — widen `execFileSyncSpy` to allow `tool_name === "Bash"` (else the now-present allowlist makes `runHookSelfTest`'s `allow[0]` probe throw and reds every handler test in the file). Run this suite too. |

Command list (run all four):

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/server/inngest/cron-cloud-task-heartbeat.test.ts \
  test/server/inngest/cron-safe-commit-parity.test.ts \
  test/server/inngest/cron-claude-eval-substrate.test.ts \
  test/server/inngest/cron-bug-fixer.test.ts
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
```

## Observability

```yaml
liveness_signal:
  what: scheduled-bug-fixer Sentry cron monitor (sentry_cron_monitor.scheduled_bug_fixer)
  cadence: daily (0 6 * * * UTC)
  alert_target: Sentry Crons missed/error check-in
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + postSentryHeartbeat (cron-bug-fixer.ts)
error_reporting:
  destination: Sentry (reportSilentFallback / warnSilentFallback in cron-bug-fixer.ts + the substrate)
  fail_loud: true — infra faults (token mint, clone, parse) set status=error; claude non-zero/no-PR is a non-paging WARN (op=claude-eval-nonzero-nofix), liveness stays green by design
failure_modes:
  - mode: stale bot-fix/* PR (auto-merge disarmed on conflict)
    detection: cron-cloud-task-heartbeat daily scan (bot-fix/* now in BOT_PR_HEAD_PREFIXES, this PR)
    alert_route: Sentry warn op=stale-bot-pr (Sentry-only — no scheduled-issue label for bot-fix/*)
  - mode: containment hook denies a prompt verb (silent no-op)
    detection: zero bot-fix/* PRs produced; the decide-paired test (AC11) is the build-time net; runtime hook self-test (runHookSelfTest) aborts the cron on a misdelivered allowlist
    alert_route: cron self-reports / monitor stays green on liveness — re-check allowlist per runbook
  - mode: token mint 403 (over-narrowed permissions)
    detection: setup-workspace clone/push failure → reportSilentFallback op=setup-ephemeral-workspace, status=error heartbeat
    alert_route: Sentry error + RED monitor
logs:
  where: Sentry events (op-tagged); app stdout pino stream (NOT shipped to Better Stack — Sentry is the off-host path)
  retention: Sentry default
discoverability_test:
  command: grep -n '"bot-fix/"' apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts  # local grep, no remote shell
  expected_output: a line inside BOT_PR_HEAD_PREFIXES
```

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — single-user-incident
threshold), Legal/compliance (CLO — autonomous code-write against prod repo).

### Engineering (CTO)

**Status:** carry-forward from #5046/#5199 Tier-2 framing.
**Assessment:** Pure infra/containment change against an already-provisioned
surface (no new server/secret/vendor → Phase 2.8 IaC gate skips; the egress
allowlist already covers bug-fixer's hosts). The architectural risk is the
prompt-rewrite (Phase 3.5) — the `$VAR`/`$(...)`/pipe constructs are the exact
containment-break class from PR 5235. Mitigation: decide-paired DENY assertions
(AC11) + the runtime `runHookSelfTest`.

### Product/UX Gate

**Tier:** none — no UI surface (no file under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`). Server/infra/docs only.
**Decision:** N/A (no UI surface).
**Pencil available:** N/A (no UI surface).

#### Findings

CPO sign-off required at plan time per `single-user incident` threshold
(`requires_cpo_signoff: true`). The product decision — "is it acceptable to run
an autonomous code-writer against the live prod repo now that the stale-PR
watchdog covers `bot-fix/*`?" — is the gate. `user-impact-reviewer` runs at PR
review.

### Legal / Compliance (CLO)

**Status:** advisory.
**Assessment:** No new regulated-data surface (no schema/migration/auth/API-route
under the canonical regex). The cron processes GitHub-issue bodies via an
Anthropic-bound LLM (existing processing activity, unchanged by this PR — bug-fixer
already did this pre-defer). gdpr-gate (Phase 2.7) trigger (a): new LLM processing
on operator-session data — but this is RE-enabling an existing activity, not a new
one; no new lawful-basis/Art.30 entry needed. Note for the work phase: if gdpr-gate
surfaces an Anthropic-DPA gap (as in #2720), file it as a separate advisory issue,
do not block this restore.

## Infrastructure (IaC)

**Skip — no new infrastructure.** This PR edits only `apps/web-platform/server/`
and `apps/web-platform/infra/sentry/` (no change) + docs. No new server, secret,
vendor, DNS, or persistent runtime process. The `cron-egress-allowlist.txt` is
UNCHANGED (bug-fixer's hosts already present). The `sentry_cron_monitor.scheduled_bug_fixer`
already exists (added with the cron in TR9 PR-5). The deploy path is the existing
`web-platform-release.yml` container restart on merge to main (`apps/web-platform/**`
path filter) — a PR merge IS the remediation for function-registry state; no
operator restart step.

## Open Code-Review Overlap

`None` — checked open `code-review`-labeled issues against the file list
(`_cron-shared.ts`, `_cron-claude-eval-substrate.ts`, `cron-bug-fixer.ts`,
`cron-cloud-task-heartbeat.ts`, `fix-issue/SKILL.md`, the three test files,
the runbook). No open scope-out names these files. (Re-run the `gh issue list
--label code-review` two-stage jq sweep at /work to confirm against live state.)

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Restore bug-fixer WITHOUT extending the watchdog (defer the watchdog to a follow-up) | **Rejected.** Creates a restore-without-watchdog window where a stale `bot-fix/*` PR rots invisibly — the exact risk that kept bug-fixer deferred. The feature description mandates atomic delivery in this PR. |
| Mirror the issue-creator allowlist shape (the 7 auto-crons) | **Rejected.** bug-fixer's commit lives in the SKILL, not safeCommitAndPr — it legitimately needs git/gh-pr persistence verbs. Mirror `cron-roadmap-review`'s git-carrying shape instead. |
| Keep the SKILL's `eval "$TEST_CMD"` / `node -e` test detection and allowlist `eval`/`node` | **Rejected.** `eval` and `node -e` are interpreters the hook denies by design (the `$ROUTER`-class bypass). The cron runs only against soleur where the runner is known — a literal `vitest run --root` is correct and strictly safer. |
| Add `bot-fix/*` to `scheduledLabelFromHead` so stale bug-fixer PRs comment on an owning issue | **Rejected.** bug-fixer files no `scheduled-bug-fixer` issue (it opens PRs), so there is no owning issue to comment on. The existing `!pr.scheduledLabel → Sentry-only` path is the correct route. |
| Broaden the egress allowlist for bug-fixer | **Rejected / unnecessary.** All four of bug-fixer's hosts (anthropic, resend, github, api.github) are already present. Broadening would violate the finite-evidence-gated discipline. |

## Research Insights (deepen pass — 2026-06-12)

Two parallel grep agents (verify-the-negative + precedent-diff, both `model: sonnet`
per ADR-053) ran against the plan. Every premise CONFIRMED (token mint at
`cron-bug-fixer.ts:636` is a bare single-key call; `BOT_PR_HEAD_PREFIXES` is
`["ci/", "self-healing/auto-"]`; `scheduledLabelFromHead` returns null for non-`ci/`;
all four egress hosts present; `TIER2_DEFERRED_CRONS = ["cron-bug-fixer"]`; bug-fixer
in `EXEMPT`). Two material corrections folded in:

1. **Allowlist tightened to the SKILL's EXACT verbs.** The first draft speculatively
   mirrored `cron-roadmap-review`'s shape (added `git switch`, `git rev-parse`,
   `gh label list/create`). The SKILL emits NONE of those — labels precreate
   node-side via `precreateLabels` (`cron-bug-fixer.ts:540`). Removed per the
   evidence-gated discipline; the allowlist is now the minimal 14-entry set above.
2. **`cron-bug-fixer.test.ts` mock widen is REQUIRED (AC12b).** The precedent agent
   caught that the existing `execFileSyncSpy` denies all non-Task/Agent/Skill tools;
   gaining an allowlist makes `runHookSelfTest`'s `allow[0]` Bash probe fire and
   throw — reding the whole file. This was unmentioned in the first draft; now an
   explicit AC + Test-Strategy row + RED-batch step + Sharp Edge.

The token-mint shape (`{ tokenMinLifetimeMs, permissions: DEFAULT_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] }`)
is an EXACT match to all 7 PR-5235 precedents (`cron-growth-audit.ts:169-172` et al.).
The AC11 decide-paired test shape mirrors the existing `#5199` block in
`cron-claude-eval-substrate.test.ts:235-287` (`v(cron, cmd)` → `decide(…, CRON_BASH_ALLOWLISTS[cron])`).

**Scheduled-work precedent (Phase 4.4):** bug-fixer is ALREADY an Inngest cron
(`cron-bug-fixer.ts`) — this is a restore, not a new scheduled job; the ADR-033
Inngest-canonical pattern is satisfied. No GH-Actions-cron alternative considered.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **The `cron-bug-fixer.test.ts` `execFileSyncSpy` mock MUST be widened to allow
  `Bash` in the SAME commit as the allowlist add.** Gaining a `CRON_BASH_ALLOWLISTS`
  entry makes `runHookSelfTest` run the `allow[0]` Bash probe; the un-widened mock
  denies it → throws → reds every handler test. RED→GREEN coupling, not optional.
- **The prompt MUST emit LITERAL allowlisted forms — no `$VAR`, no `NAME=`, no
  `$(...)`, no pipes/redirects in hook-gated bash.** This was the PR 5235
  community-monitor containment break. AC11's decide-paired DENY assertions are
  vacuous unless paired with REAL-prompt ALLOW assertions — keep both.
- `git add` blanket forms (`-A`, `--all`, `-u`, `.`, absolute paths, `.claude/`)
  are denied by `gitVerbReason`; the prompt must emit `git add -- <literal-path>`.
  `git commit -a`/`--all` is also denied. The parity test invariant 1 greps the
  cron SOURCE for blanket-add literals — keep the SKILL's scoped form.
- `gh pr merge` is a `PERSISTENCE_PREFIX` (forbidden) — bug-fixer arms auto-merge
  via the node-side GraphQL mutation, NOT a prompt verb. Do NOT allowlist it.
- bug-fixer stays in `cron-safe-commit-parity.test.ts` `EXEMPT` — do NOT add it
  to `MIGRATED_PROMPT`/`MIGRATED_HANDLER` (invariant 4's `EXEMPT`-disjoint check
  reds if you do; invariants 2/3 would also fire because it has no
  `safeCommitAndPr` call).
- Test file paths must satisfy vitest's `include:` globs (`test/**/*.test.ts`).
  All three target files already live there — do not co-locate.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, NOT
  `npm run -w` (no root `workspaces` field). Runner is vitest, NOT `bun test`.
- `Closes #5199` (not `Ref`) — this is a code-class PR whose fix lands at merge,
  not an ops-remediation executed post-merge.
- When rewriting the `_cron-shared.ts` deferral block comment, do not orphan the
  `roadmap-review (#5004) is ABSENT` note — it's still true (roadmap-review was
  always Tier-1, never in the set).
