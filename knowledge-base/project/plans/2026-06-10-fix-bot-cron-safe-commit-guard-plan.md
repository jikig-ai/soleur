---
title: "fix: deterministic safe-commit guard for soleur-ai bot PR pipelines"
date: 2026-06-10
type: fix
lane: cross-domain
closes: "#5091"
brand_survival_threshold: aggregate pattern
---

# fix: deterministic safe-commit guard for soleur-ai bot PR pipelines (#5091)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed; no spec.md exists for this branch).
> Revised 2026-06-10 after 3-agent plan review (DHH / Kieran / code-simplicity) — see `## Plan Review Synthesis`.

## Overview

The weekly SEO/AEO audit cron produced destructive PR #5026: −107,368 lines, deleting the entire `plugins/soleur/` tree (654 files) and modifying `.claude/settings.json`. CI's 8 required checks caught it; the PR was closed with no damage to main.

**Root cause (deterministic, not a flake).** `setupEphemeralWorkspace` (`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts:305-309`) `rm -rf`s the cloned `repo/plugins/soleur` and symlinks it to the host plugin dir, and overwrites the tracked `.claude/settings.json` with the cron permission overlay (`:322-326`). From clone-git's perspective, **every run** of every substrate-based cron sees 654 tracked-file deletions + 1 modification. The `SEO_AEO_AUDIT_PROMPT`'s `MANDATORY FINAL STEP` runs blanket `git add -A` (`cron-seo-aeo-audit.ts:121`), staging all of it. The hazard is structural in all three `git add -A` prompts (seo-aeo-audit, content-generator:121, growth-execution:129); the same-week clean content-gen run (#4983) was luck, not safety.

**Fix (operator-approved scope: generalize to all soleur-ai bot PR pipelines, applied as: deterministic shared helper now for the dangerous class + mechanical guards for the live class + one consolidation follow-up for the already-scoped class).**

1. **Phase 0 root-cause spike (DHH P0):** the clone of main *already contains* the full tracked `plugins/soleur` tree. Test whether headless `claude --print --plugin-dir` resolves against (a) the clone's own tracked copy or (b) an absolute out-of-tree host path. If either works, delete the `rm -rf` + symlink from the substrate **in this PR** — the 654 phantom deletions cease to exist, and bot edits to plugin docs become committable (dissolving the symlink-shadow defect for seo-aeo/growth-execution/content-gen's primary output). Timeboxed; decision gate below.
2. **`safeCommitAndPr()`** — one deterministic, non-throwing, replay-idempotent TS helper replacing the `MANDATORY FINAL STEP` shell blocks of the **3 blanket-add crons**. The prompt is a suggestion to a model; the contamination is a substrate artifact the model cannot reason about. This consolidates an existing pattern (5 non-claude-spawn crons already commit handler-side: `cron-weekly-analytics.ts:253-310` et al.) — the prompt-level commit blocks are the outliers.
3. **Containment-hook hardening — the only layer protecting LIVE code.** `cron-roadmap-review` is Tier-1, live, runs in the same contaminated substrate, and its allowlist permits bare `git add`/`git commit` — a model-improvised `git add -A` (or scoped `git add plugins/`) reproduces #5026 *today*. The hook deny set + a pathspec deny + an explicit prompt line close this. This is P1 protection, not garnish.
4. **fix-issue skill** scoped add (cron-bug-fixer surface).
5. **Parity test** that mechanically enforces the invariants (including the Tier-2 restoration constraint — a test, not prose in PR bodies).

Per `hr-never-git-add-a-in-user-repo-agents` (scoped adds, never blanket) and `cq-silent-fallback-must-mirror-to-sentry` (every dropped/aborted path mirrors to Sentry).

## Premise Validation & Research Reconciliation — Issue vs. Codebase

| Issue/args claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "the fix lives in the soleur-ai app's cron job definition / the seo-aeo skill's commit step" | Commit step is the `SEO_AEO_AUDIT_PROMPT` template literal in `cron-seo-aeo-audit.ts:110-129` (Inngest function), NOT the seo-aeo skill. 3 prompts use `git add -A`; 4 more use scoped adds (campaign-calendar:103, growth-audit:104, community-monitor:190, competitive-analysis:141); 5 further crons commit handler-side with scoped `spawnGitChecked` adds; roadmap-review (live) improvises git within a bash allowlist. | Migrate the 3 blanket-add crons to the helper; hook-harden the live path; consolidate the rest via follow-up. `fix-issue/SKILL.md:160` carries `git add -A` — swept in. |
| "working tree was missing/partially checked out" | Deterministic substrate design: symlink replacement + settings overlay = 654 D + 1 M on every run. Not a partial checkout. | Phase 0 spike attacks the root cause; structural prefix exclusions + deletion guard as defense-in-depth either way. |
| "abort if deletions exceed a sane threshold" (issue suggested N=50) | Plan picks **DEFAULT_MAX_DELETIONS = 10** (module constant, not per-cron config): above incidental renames (a rename = 1 worktree `D`), far below 654. Divergence from the issue's 50 recorded here and in the PR body. | Constant; add an override param only when a cron actually needs one. |
| Issue AC: "abort if staged diff touches `.claude/settings.json` or `plugin.json`" | The substrate **guarantees** those appear dirty on every run — abort-on-touch would abort every run. | Deliberate reinterpretation (state in PR body): `.claude/` and `plugins/soleur/` are structurally excluded from staging (never committed); the abort guard applies to deletions within allowed paths. If Phase 0 removes the symlink, the exclusion shrinks to `.claude/` only. |
| "verify next weekly audit run ~2026-06-15 produces a sane PR" | All 7 claude-spawn prompt-commit crons are **Tier-2-deferred** (`TIER2_DEFERRED_CRONS`, `_cron-shared.ts:222-234`, #5018): `deferIfTier2Cron` posts a deferral heartbeat and never spawns claude — including manual triggers. 2026-06-15 will be a deferral no-op. | Verification = scratch-git-repo unit harness (the code ships dormant); live verification deferred to Tier-2 restoration; sequencing invariant enforced by the parity test. PR body closes the loop on the issue's AC3 explicitly. |
| (new finding) | The `plugins/soleur` symlink is **read-write**: bot edits to `plugins/soleur/**` (seo-aeo docs fixes, growth page fixes, content-writer's default `plugins/soleur/docs/blog/` articles) mutate the HOST plugin dir and are invisible to clone-git. | Phase 0 spike attempts the fix in this PR. Only if the spike fails: follow-up issue + the dead-config comments in the allowedPaths table stand. |
| (new finding) | 5 live crons (weekly-analytics, compound-promote, content-publisher, content-vendor-drift, rule-prune) have private handler-side commit pipelines with scoped adds but no deletion guard; 4 dormant prompt crons use scoped adds. Both classes are already safe from the #5026 class. | One consolidation follow-up issue (9 crons → `safeCommitAndPr`, opportunistic, migrate-when-touched). Parity test exempts them explicitly. |
| #5026 / #4983 cited in args | Both are PRs (closed/merged), contextual citations — confirmed not work targets. | No action. |

## User-Brand Impact

**If this lands broken, the user experiences:** bot content/audit PRs stop landing (articles, audit fixes silently stop) or a structurally incomplete bot PR auto-merges — degraded docs/marketing surface for all Soleur users. Main-branch integrity remains protected by the 8 required CI checks, unchanged by this PR, which already caught #5026.

**If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector. The helper handles the GitHub installation token already held by the handler; it never logs it (reuses `redactToken`), and the spawned model's env allowlist is unchanged.

**Brand-survival threshold:** aggregate pattern — a single broken bot PR is caught by required checks; brand cost accrues only if the pipeline degrades persistently across runs. (Threshold `none` does not apply: this code path writes to the public repo.)

## Phase 0 — Substrate spike (decision gate, timeboxed ~1h)

Question: does headless `claude --print --plugin-dir plugins/soleur` skill resolution (the #4993/#4987 constraint) work against the clone's **own tracked** `plugins/soleur` (no rm/symlink), or against an **absolute out-of-tree** `--plugin-dir <host-path>`?

Method: locally replicate `setupEphemeralWorkspace` minus the rm+symlink (fresh `git clone --depth=1` of this repo, write `.claude/settings.json` overlay + `cron-allow.txt`), then `claude --print --plugin-dir plugins/soleur -- "Run /soleur:help"` (or any cheap skill-resolution probe) and assert the skill resolves. Repeat with `--plugin-dir /abs/path/to/host/plugin`.

- **Outcome A (either form works):** delete `rm`/`symlink` lines from `setupEphemeralWorkspace` (keep the plugin-manifest sentinel check against the resolved dir); structural exclusion shrinks to `.claude/` only; the symlink-shadow defect dissolves (plugin-docs edits become committable); skip the symlink-shadow follow-up issue. Keep the deletion guard (defends future contamination classes).
- **Outcome B (neither works / inconclusive within the timebox):** keep the symlink; structural exclusion = `.claude/` + `plugins/soleur/` prefixes; file the symlink-shadow follow-up issue; record the *actual* reason the alternatives fail in this plan's table (replacing the strawman).

The helper and all other phases are identical under both outcomes — only the exclusion constant and the follow-up issue differ.

## Design

### `safeCommitAndPr()` — contract

New file `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`. Underscore prefix keeps it out of `function-registry-count.test.ts` enumeration (its filter is `startsWith("cron-")`, verified at `:67`). Use the relative `./_cron-shared` import form to match sibling convention (note: `cron-substrate-imports.test.ts` skips `_`-prefixed files, so convention is followed by choice, not enforced there).

```ts
const DEFAULT_MAX_DELETIONS = 10; // module constant; issue suggested 50 — divergence recorded in PR body

export interface SafeCommitConfig {
  spawnCwd: string;
  installationToken: string;        // octokit PR create + auto-merge
  cronName: string;                 // branch prefix derived: cronName.replace(/^cron-/, "")
  commitMessage: string;
  prTitle: string;
  prBody: string;
  allowedPaths: readonly string[];  // path prefixes, repo-root-relative
  runStartedAt: string;             // handler's memoized ISO string
  scheduledIssueLabel: string;      // for the guard/fail visibility comment
}

export type SafeCommitResult =
  | { status: "committed"; prNumber: number; branch: string }
  | { status: "no-changes" }
  | { status: "failed"; stage: "workspace-lost" | "status" | "deletion-guard" | "add" | "commit" | "push" | "pr-create" | "auto-merge"; message: string };
```

**Non-throwing contract (spec-flow P0-2):** every failure path returns `{status:"failed",...}` after mirroring to Sentry via `reportSilentFallback` — it NEVER throws (a throw inside the step would fail the Inngest run before `sentry-heartbeat`/`ensure-audit-issue`, silencing the observability chain). Step return is bounded (no full file lists — counts + ≤10-path samples go to Sentry, not the step output).

**Algorithm:**

1. **Workspace-lost check.** `spawnCwd` missing (replay after container restart with memoized `setup-workspace`) → `failed/workspace-lost`, Sentry op `safe-commit-workspace-lost`. Never conflated with `no-changes`.
2. **Replay-resume check (Kieran P2-5).** If the current branch is already `ci/<prefix>-<ts>` with a commit whose committer matches the bot identity (mid-step crash between commit and push on a prior attempt), **resume at push** — do not re-scan, do not misattribute. Use `git checkout -B` when (re)creating the branch.
3. **Scan.** `git status --porcelain=v1 -z --untracked-files=all` (`-u all` is load-bearing: without it, new files inside an untracked dir collapse to one `dir/` entry, defeating per-file filtering). Rename-aware parsing: `R`/`C` entries under `-z` carry TWO NUL-terminated fields, **destination first, source second** — consume both, take the destination, or every subsequent entry misaligns (verified empirically; precedent `knowledge-base/project/learnings/2026-04-27-autoloop-pr-quality-failure-modes.md`). Count a deletion when `D` appears in either the X or Y column.
4. **Structural exclusion (Kieran P0 — prefix, not literal entry).** Drop any path equal to or under `.claude/` — and, under Phase 0 Outcome B, equal to or under `plugins/soleur/` (the symlink swap produces `?? plugins/soleur` PLUS 654 `D` entries for paths *under* it; a literal-entry exclusion would let those deletions match the allowlists and trip the guard on every run). Structural drops are silent by design (they recur every run); the lift-condition is recorded in the symlink-shadow follow-up.
5. **Allowlist filter.** Keep paths matching an `allowedPaths` prefix. If any non-structural path is dropped, `reportSilentFallback` op `safe-commit-paths-dropped` `{droppedCount, sample}` — a silently truncated PR that auto-merges green is the P1-1 failure mode (e.g. an article without its queue annotation regenerates the same topic forever).
6. **Deletion guard.** Deletions among *matched* paths > `DEFAULT_MAX_DELETIONS` → `failed/deletion-guard`; Sentry op `safe-commit-deletion-guard` `{deletionCount, max, sample}`. No branch, no commit, no PR.
7. **No changes.** Zero matched paths → `no-changes` + structured log with cronName (greppable signature; the symlink-shadow class lands here under Outcome B).
8. **Commit.** Branch `ci/<prefix>-<ts>`, `ts` derived from `runStartedAt` as `YYYY-MM-DD-HHMMSS` (**strip `:` and `.` — raw ISO is refname-illegal and fails every push**, spec-flow P1-7). `git add -- <explicit matched files>` (never `-A`). Identity AND dates via env: `GIT_AUTHOR_NAME/EMAIL`, `GIT_COMMITTER_NAME/EMAIL` ("github-actions[bot]" / "41898282+github-actions[bot]@users.noreply.github.com"), `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` = `runStartedAt`. Deterministic dates ⇒ replay-stable commit SHA ⇒ idempotent push across Inngest `retries:1` (the load-bearing property; node-level spawn is outside the containment hook's jurisdiction, so `git config` would also work — env form chosen for SHA determinism).
9. **Push.** `git push -u origin <branch>`. Failure → Sentry with `redactToken`-scrubbed stderr; message notes a 401 can mean the memoized installation token expired across a delayed replay (P2-1).
10. **PR create.** octokit `POST /pulls` (pattern: `cron-weekly-analytics.ts:285`). **422 "A pull request already exists" = success** (replay tolerance): recover the number via `GET /pulls?head=jikig-ai:<branch>`.
11. **Auto-merge.** GraphQL `enablePullRequestAutoMerge` — extract/reuse `cron-bug-fixer.ts:441-481` (already tolerates "already enabled"); ADD tolerance for **"Pull request is in clean status"** (path-filtered required checks may never report on knowledge-base-only diffs and arming auto-merge would hang forever) → fall back to direct `PUT /pulls/{n}/merge`. Branch cleanup: repo has `delete_branch_on_merge=true` (verified via `gh api`) — rely on it; no manual ref deletion.
12. **Visibility comment (spec-flow P1-2).** On `failed` (any stage, incl. deletion-guard): best-effort comment on the run's scheduled issue (most recent open issue with `scheduledIssueLabel`): `"PR withheld: <stage> — <short reason>. See knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md."` Wrapped: a comment failure mirrors to Sentry, never crashes teardown. (A non-technical operator otherwise sees an issue saying "fixes applied" with no PR anywhere.)

### Handler wiring & step ordering (spec-flow P0-1)

Commit gate = **issue-verified output**, not the spawn exit code. New step order in each migrated handler:

```
deferIfTier2Cron → run-started-at → mint-installation-token → setup-workspace
  → claude-eval
  → verify-output            (resolveOutputAwareOk — unchanged semantics)
  → safe-commit-pr           (step.run; ONLY when heartbeatOk === true && !spawnResult.abortedByTimeout)
  → sentry-heartbeat         (unchanged)
  → ensure-audit-issue       (unchanged fallback when !heartbeatOk)
```

Rationale: `spawnResult.ok` inverts on both max-turns permutations. (a) exit 0 + edits + NO issue = unverified, possibly mid-edit partial work — must NOT auto-merge (the #5026 damage class, vector swapped); `heartbeatOk=false` skips the commit and the FAILED self-report fires. (b) issue created + non-zero exit (documented healthy `scheduled-output-nonzero-exit` case, observed on competitive-analysis #4747) — commit proceeds; gating on `spawnResult.ok` would silently discard the diff under a green monitor. The `!abortedByTimeout` clause deliberately discards a diff from a timed-out run even when the issue exists: a 30-min hard kill can land mid-edit, and partial work must not ship (rationale stated here per Kieran P2-7; the discard is visible via the timeout's existing `reportSilentFallback`).

Verify per handler that `run-started-at` is a memoized step (it is in `cron-seo-aeo-audit.ts:170-173`; confirm in the other two before wiring — a handler computing it inline breaks SHA determinism).

### Prompt changes (3 files)

Remove the `MANDATORY FINAL STEP` git/PR shell block from the 3 blanket-add prompts **and scrub the header comments that reference it** (Kieran P2-3: `grep -c "MANDATORY FINAL STEP"` currently 4 in seo-aeo, 4 in growth-execution — comments included; AC2 requires 0). Replacement anchor paragraph (becomes the asserted test anchor — anchors are *replaced*, not deleted, preserving the verbatim-extraction discipline):

```
PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
```

Keep each prompt's issue-creation step (the output contract) untouched. Test sentinels: `Do NOT run git add` and `opens a PR for your changes` (no punctuation-boundary spans; verify against the as-written literal before committing tests — paren-safety learning 2026-05-15).

### Per-cron config (3 migrated crons)

Derived from verified write targets; the dropped-paths Sentry warn surfaces under-enumeration in production rather than silently truncating.

| Cron | allowedPaths | Notes |
| --- | --- | --- |
| cron-seo-aeo-audit | `plugins/soleur/docs/` | Under Phase 0 Outcome B this is dead config (structurally excluded) — annotate with a comment pointing at the symlink-shadow follow-up; the run lands `no-changes` honestly instead of destructively. Under Outcome A it is live. (Kieran P2-2: `seo-refresh-queue.md` dropped — not a verified seo-aeo write target.) |
| cron-content-generator | `knowledge-base/marketing/`, `plugins/soleur/docs/blog/` | Marketing paths verified via #4983; blog default path per `content-writer/SKILL.md:58` (Outcome-B-dead, same annotation). |
| cron-growth-execution | `knowledge-base/marketing/`, `plugins/soleur/docs/` | Queue + page fixes; `_site/` is gitignored (local eleventy build never enters the scan). |

Branch names: `ci/<cronName minus cron->-<YYYY-MM-DD-HHMMSS>` — keeps the `ci/` lineage greppable; prefix derived, not configured.

### Hook hardening (the live-path P1 fix)

`cron-bash-allowlist-hook.mjs` `gitVerbReason` gains a **flag-position-independent** deny set (spec-flow P1-4; naive `-A|--all|.` is hollow):

- `git add` with any of: `-A`/`--all` (incl. clustered `-fA`, `-vA`), `-u`/`--update` (**stages all tracked deletions — the exact #5026 vector**), a `.`/`./`/`:/` pathspec, a literal `*` token, **or any pathspec resolving under `plugins/soleur` or `.claude`** (DHH P1-1: a "scoped" `git add plugins/` stages all 654 deletions; the contamination prefixes are deniable by name).
- `git commit` with `-a`/`--all`/clustered `-am` (bypasses `git add` entirely).
- Deny reasons are **instructive** (Kieran P1): e.g. `"blanket git add denied — stage only the specific files you edited: git add <paths>"` so a live mid-run model self-corrects on retry.

Implementation: tokenize args after the subcommand; explode clustered single-dash flags before matching. `cron-bash-allowlist-hook.test.ts:46` (`git add -A && git commit -m "roadmap sync"` → allow) FLIPS to deny. Roadmap-review is LIVE — the plan does NOT claim zero live impact (Kieran P1): mitigations in the same PR: (a) one line added to `ROADMAP_REVIEW_PROMPT`: "stage only the specific files you edited — never `git add -A`, `-u`, or `.`"; (b) the instructive deny reason above; (c) roadmap-review prompt-anchor test updated for the new line.

### fix-issue skill (cron-bug-fixer surface)

`plugins/soleur/skills/fix-issue/SKILL.md:160`: replace `git add -A` with a scoped add of the **enumerated changed files from the fix phase** (fix file + any test file — not a hardcoded single path; spec-flow P2-2).

### Parity guard test (mechanical invariants, no fuzzy classifier)

New `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` (readdirSync pattern per learning 2026-06-07; simplified per panel — no comment-sensitive classifier, no `EXPECTED_COUNT`):

1. **Literal scan:** no file under `server/inngest/functions/^(cron|event)-.*\.ts$` (nor the hook `.mjs`) contains `git add -A`, `git add --all`, or `git add -u` — full source including comments (keep new code comments clear of the literals; AC1's grep covers the hook file too).
2. **Migrated list (explicit):** `cron-seo-aeo-audit.ts`, `cron-content-generator.ts`, `cron-growth-execution.ts` each import and call `safeCommitAndPr` and contain the `Do NOT run git add` prompt anchor; assert `migrated.length >= 3` style minimum-bound, not an exact count.
3. **Tier-2 restoration constraint (DHH P1-2 — test, not prose):** for every migrated cron, its `CRON_BASH_ALLOWLISTS` entry (if present) contains NO `git add` / `git commit` / `git push` / `gh pr create` / `gh pr merge` prefix — a Tier-2 restoration that re-arms prompt-side commits fails CI instead of relying on a PR-body memo.
4. **Exempt list with rationale comments:** the 5 legacy `spawnGitChecked` pipelines + the 4 scoped-add prompt crons (consolidation follow-up) + `cron-roadmap-review` (live Tier-1; guarded by the hook deny set above).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — Phase 0 Outcome A only: remove rm+symlink (keep manifest sentinel against the resolved plugin dir).
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — prompt block + header-comment scrub, safe-commit step wiring, config.
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — same.
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — same.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — one prompt line: stage only specific files (live-path mitigation).
- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` — extract auto-merge GraphQL mutation (`:441-481`) into the helper module; re-point import; no behavior change.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — `gitVerbReason` deny set + instructive reasons.
- `plugins/soleur/skills/fix-issue/SKILL.md` — scoped add at `:160`.
- `apps/web-platform/test/server/inngest/cron-seo-aeo-audit.test.ts` — anchor replacement + gating assertion.
- `apps/web-platform/test/server/inngest/cron-content-generator.test.ts` — same.
- `apps/web-platform/test/server/inngest/cron-growth-execution.test.ts` — same.
- `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` — new prompt-line anchor.
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts` — flip `:46`; deny/allow matrix.
- `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts` — read first; extend only if it asserts prompt commit blocks.

## Files to Create

- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` — the helper.
- `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` — unit tests with a **scratch git fixture repo** (`mkdtemp` + `git init`, ~15 seeded tracked files — right-sized per panel; the guard compares `count > 10`, 600 files prove nothing 15 don't): symlink-contamination scenario → structural exclusion + guard; rename `-z` two-field parsing; untracked-dir expansion; refname validity (no `:`/`.`); pinned `GIT_*_DATE`/identity env asserted on the commit spawn (+ one cheap double-run SHA-equality on the tiny fixture); replay-resume (HEAD already on `ci/*` with bot commit → push path, not re-scan); 422-tolerant PR create (mocked octokit); clean-status auto-merge fallback (mocked); non-throwing failure paths. This is the verification story while the crons are Tier-2-deferred (the code ships dormant; first live exercise is post-restoration `cron/<name>.manual-trigger`).
- `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` — the 4 mechanical invariants above.

## Implementation Phases (contract-first ordering)

0. **Substrate spike** (decision gate above; timebox ~1h; record outcome + evidence in the PR body and this plan).
1. **Helper + unit tests (RED → GREEN)** per `cq-write-failing-tests-before`; extract bug-fixer's auto-merge mutation; re-point its import.
2. **Migrate the 3 blanket-add crons** (prompts incl. header-comment scrub + handler wiring + 3 anchor-test updates). Seo-aeo first (the incident cron), then the other two mechanically.
3. **Hook deny set + test matrix + roadmap-review prompt line + its anchor test.**
4. **fix-issue SKILL.md scoped add.**
5. **Parity test; full gates:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run test/server/inngest/ test/server/cron-substrate-imports.test.ts test/server/cron-no-byok-lease-sweep.test.ts` (Kieran P2-4: those two live under `test/server/`, NOT `test/server/inngest/`; NOT `npm run -w` — no root `workspaces` field; NOT `bun test` — vitest + `bunfig.toml` block).
6. **Follow-up issues** (`gh issue create`, labels verified via `gh label list` before use; milestone per `knowledge-base/product/roadmap.md`):
   - **Consolidation migration** (one issue): migrate the 4 scoped-add prompt crons (campaign-calendar, growth-audit [path is `knowledge-base/marketing/audits/soleur-ai/` — verbatim], community-monitor, competitive-analysis) + the 5 legacy `spawnGitChecked` pipelines to `safeCommitAndPr`; opportunistic (migrate-when-touched), honest framing: consolidation, not urgent debt. Include: one-line decision on a stale-`ci/*`-PR watchdog at Tier-2 restoration (auto-merge silently disarms on conflict; campaign-calendar and growth crons share `knowledge-base/marketing/` files); ADR authorship ("deterministic handler-side commit as THE write path") belongs here, when it becomes true — not in this PR where 9 exemptions would falsify it.
   - **Symlink-shadow** (ONLY under Phase 0 Outcome B): bot edits to `plugins/soleur/**` mutate the HOST plugin dir and are invisible to clone-git; includes the exclusion lift-condition (when fixed, remove the `plugins/soleur/` structural exclusion or legit plugin-docs work is silently dropped with only the `no-changes` log as signal).

## Sequencing invariant (Tier-2 interaction)

`feat-tier2-cron-egress-firewall-pr2` touches the same cron files, substrate, hook, and hook test (verified by diffstat — NOT infra-only). **Merge order: this PR first; Tier-2 rebases on top.** The hard invariant — Tier-2 un-deferral of a PR-producing cron must not precede `safeCommitAndPr` wiring — is enforced **mechanically** by parity-test invariant 3 (allowlist exclusion) and invariant 2 (migrated-list), not by prose. One sentence in the Tier-2 PR body points at the test.

## Acceptance Criteria

### Pre-merge (PR)

1. `grep -rn "git add -A" apps/web-platform/server/inngest/ plugins/soleur/skills/fix-issue/` → 0 matches (includes the hook `.mjs` and all comments; current baseline is exactly 4 hits).
2. `grep -c "MANDATORY FINAL STEP" apps/web-platform/server/inngest/functions/cron-{seo-aeo-audit,content-generator,growth-execution}.ts` → 0 per file (comments scrubbed too; baseline 4/≥1/4); `grep -c "Do NOT run git add"` → ≥1 per file.
3. `_cron-safe-commit.ts` exports `safeCommitAndPr` returning the 3-variant `SafeCommitResult`; the non-throwing contract is asserted by unit test (every failure stage returns `failed`, never throws).
4. Unit tests prove: (a) fixture with tracked-file deletions under the structural-exclusion prefix + 2 legit changes commits ONLY the 2, zero guarded deletions; (b) 11 deletions inside allowedPaths → `failed/deletion-guard`; (c) rename `-z` parsing does not misalign subsequent entries; (d) commit spawn env carries pinned `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` = `runStartedAt` + bot identity, and a double run on the same fixture yields identical SHAs; (e) PR-create 422 resolves to `committed` with the recovered PR number; (f) branch name is refname-valid (no `:` or `.`); (g) replay-resume: HEAD already on `ci/*` with the bot commit → proceeds to push without re-scan.
5. Each migrated handler calls `safeCommitAndPr` in a `step.run` gated on `heartbeatOk === true && !spawnResult.abortedByTimeout` (asserted via step-sequence mock in each cron's test).
6. Hook test matrix: deny `git add -A`, `git add --all`, `git add -u`, `git add -fA`, `git add .`, `git add -A -- .`, `git add *`, `git add plugins/soleur/docs/x.md`, `git add .claude/settings.json`, `git commit -am "x"`, `git commit -a`; allow `git add knowledge-base/foo.md`, `git commit -m "x"`. Deny reasons contain actionable retry guidance.
7. Parity test green: literal scan, 3-entry migrated list (minimum-bound), allowlist-exclusion invariant, 10-entry exempt list with rationale.
8. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/server/inngest/ test/server/cron-substrate-imports.test.ts test/server/cron-no-byok-lease-sweep.test.ts` green; `function-registry-count.test.ts` untouched (no `cron-` file added/removed).
9. PR body: `Closes #5091`; Phase 0 outcome + evidence; the issue-AC2 reinterpretation (structural exclusion vs abort-on-touch) and the N=10-vs-50 divergence; the Tier-2 sequencing note pointing at the parity test; live-verification deferral (the ~2026-06-15 run is a deferral no-op — issue AC3 renegotiated to the scratch-repo harness); link(s) to the follow-up issue(s); explicit non-goal: the guard counts deletions only — mass *modification* within allowedPaths is unguarded by design, required CI checks are the backstop.

### Post-merge (operator)

None. All verification is automated pre-merge (the migrated code path is Tier-2-dormant); follow-up issues are created in-session via `gh issue create`. Automation: nothing operator-only remains.

## Open Code-Review Overlap

None (checked `gh issue list --label code-review --state open --limit 200` against every Files-to-Edit path on 2026-06-10; zero body matches).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO advisory — handler-side deterministic commit is the correct layer (consolidates the existing 5-cron `spawnGitChecked` pattern; prompt-level adds are structurally inferior: the contamination is a substrate artifact the model cannot reason about). Folded in: deterministic commit dates for replay-idempotent push; 422-tolerant PR create; clean-status auto-merge fallback (the `enablePullRequestAutoMerge`-hangs-forever trap on path-filtered checks); `--untracked-files=all`; `git commit -a` deny; exempt-list discipline; Tier-2 merge-order sequencing. ADR deferred to the consolidation follow-up (where "sole write path" becomes true).

### Product/UX Gate

Not applicable — no UI-surface files (mechanical override checked: no `components/**`, `app/**/page.tsx`, `.njk`, or UI-surface paths). Tier: NONE.

### SpecFlow

**Status:** reviewed
**Assessment:** 9 flows walked; both P0s folded (commit gate = issue-verified output, not exit code; non-throwing replay-idempotent helper), P1s addressed (dropped-path warn, guard-abort issue comment, rename parsing, hook deny completeness incl. `-u` and pathspec denies, auto-merge fallbacks, refname sanitization, symlink-shadow visibility via Phase 0/no-changes log), P2s recorded (token-expiry message, fix-issue multi-file add, mass-modification non-goal, anchor replacement, scratch-repo verification story).

## Plan Review Synthesis (applied 2026-06-10)

- **DHH P0 → Phase 0 substrate spike** (attack the contamination, don't instrument around it); strawman row in Alternatives replaced by the spike's decision gate. **DHH P1-1 →** hook pathspec deny for `plugins/soleur`/`.claude` + live-path framing. **DHH P1-2 →** Tier-2 constraint is parity-test invariant 3; follow-up issue 4 deleted. **DHH P2 →** branch-delete clause cut (repo `delete_branch_on_merge=true` verified); `EXPECTED_COUNT` → minimum bound; `branchPrefix` derived; follow-ups 4 → 1-2.
- **Kieran P0 →** structural exclusion is the `plugins/soleur/` PREFIX (literal-entry reading would re-create #5026 as a permanent abort on all three crons). **Kieran P1s →** parity test has no comment-sensitive classifier (mechanical literal scan + explicit list); roadmap-review live impact acknowledged + mitigated (prompt line, instructive deny, anchor test). **Kieran P2s →** growth-audit verbatim path recorded in follow-up; seo-refresh-queue dropped from seo-aeo row; AC2 includes header-comment scrub with baselines; Phase 5 vitest invocation fixed for `test/server/` locations; substrate-imports citation corrected (convention, not enforcement); replay-resume branch added to the algorithm + AC4(g); timeout-skip rationale stated.
- **Simplicity →** migration scope 7 → 3 crons (the 4 scoped-add dormant crons join the legacy-5 in one consolidation follow-up — by the plan's own exemption logic); `warnOnNoChanges` cut (structured `no-changes` log suffices; the condition is already issue-tracked); `maxDeletions` → module constant with divergence note; result union 4 → 3 variants; visibility comment lives in the helper (no 3× handler duplication); fixture right-sized; ADR deferred.

## Observability

```yaml
liveness_signal:
  what: existing per-cron Sentry Crons monitors (e.g. scheduled-seo-aeo-audit) — unchanged; heartbeat still keyed to issue-verified output
  cadence: per cron schedule (weekly/biweekly)
  alert_target: Sentry Crons → existing operator alert rules
  configured_in: apps/web-platform/infra/sentry/ (existing; no new monitors)
error_reporting:
  destination: Sentry via reportSilentFallback ops — safe-commit-deletion-guard, safe-commit-paths-dropped, safe-commit-workspace-lost, plus per-stage failed events
  fail_loud: helper is non-throwing but EVERY non-committed outcome mirrors to Sentry; failures additionally comment on the run's scheduled issue
failure_modes:
  - mode: deletion guard trips (contamination class reaches allowedPaths)
    detection: Sentry op safe-commit-deletion-guard (count + sample) + "PR withheld" issue comment
    alert_route: Sentry issue alert (existing silent-fallback routing)
  - mode: push/PR-create/auto-merge failure (token expiry, GitHub 5xx, conflict)
    detection: Sentry per-stage failed events with redacted stderr; replay tolerance via deterministic SHA + 422 handling
    alert_route: Sentry issue alert
  - mode: run verified but zero committable changes (symlink shadow, Outcome B)
    detection: structured no-changes log keyed by cronName; tracked by the symlink-shadow follow-up issue
    alert_route: log warehouse query (non-paging; known-tracked condition)
logs:
  where: pino structured logs in the Inngest handler (existing transport); Sentry events carry bounded path samples
  retention: existing platform retention (Better Stack/Sentry defaults)
discoverability_test:
  command: 'gh pr list --search "head:ci/" --state all --limit 5 && gh issue list --label scheduled-seo-aeo-audit --limit 3'
  expected_output: bot PRs and scheduled issues enumerable without SSH; guard aborts visible as issue comments
```

## Test Scenarios

No browser/UI flows (QA skill: skip gracefully). Command-line verification:

1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit.test.ts` — green (AC4 scenarios).
2. `./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit-parity.test.ts test/server/inngest/cron-bash-allowlist-hook.test.ts` — green (AC6/AC7).
3. `./node_modules/.bin/vitest run test/server/inngest/ test/server/cron-substrate-imports.test.ts test/server/cron-no-byok-lease-sweep.test.ts` — green.
4. AC1/AC2 greps return the stated counts.

## Risks & Mitigations

- **Tier-2 rebase conflicts (likelihood reduced by the 3-cron scope):** PR-2 touches the hook + hook test + substrate. Mitigation: merge-order agreement (this first), parity-test-enforced invariant, surgical diffs.
- **Phase 0 Outcome A regression risk (substrate change):** plugin-manifest sentinel check retained; spike evidence in PR body; the change is a deletion of contamination, not new machinery. If anything is ambiguous, fall back to Outcome B (additive-only PR).
- **Hook deny flips live roadmap-review behavior:** mitigated by prompt line + instructive deny reason + PreToolUse feedback loop (the model retries scoped). Not claimed zero-impact.
- **False-positive guard aborts on legit >10-file changes:** conservative by design; the Sentry event carries the count and sample; raising the constant is a one-line reviewed change.
- **Model writes malicious content within allowedPaths:** explicit non-goal — required CI checks are the backstop; the guard bounds *structural* damage.

## Alternative Approaches Considered

| Alternative | Why rejected |
| --- | --- |
| Prompt-level scoped `git add` only (minimal diff) | Prompts are advisory to a model; max-turns exhaustion drops prompt tails (learning 2026-06-03 — community-monitor lost its final step for 9 days); the containment hook denies the shell forms a prompt-side guard needs. Deterministic TS is the only enforceable layer. |
| Keep the symlink, make git blind to it (skip-worktree / sparse checkout) | Fragile git-internals; superseded by the Phase 0 spike which tests removing the symlink need entirely. Under Outcome B, the *actual* blocker gets recorded here. |
| Hook-only enforcement (keep prompt commit blocks) | The hook only governs hooked crons; doesn't fix scoping, idempotency, or the issue-verified gate. Kept as the live-path layer, not the whole fix. |
| Migrate all 7 prompt crons + 5 legacy pipelines now | 4 prompt crons + all 5 legacy pipelines already use scoped adds — not the P1 vector, dormant or live-and-working; same blast-radius logic both ways (panel consensus). Consolidation follow-up. |

## Sharp Edges

- Structural exclusion is PREFIX-based (`plugins/soleur/`, `.claude/`) — a literal-entry exclusion re-creates #5026 as a permanent deletion-guard abort (Kieran P0).
- New code comments must not contain the literals `git add -A`/`git add --all`/`git add -u` anywhere under `server/inngest/` including the hook `.mjs` (AC1 grep + parity scan cover comments).
- Test anchors: verify every `toContain` sentinel against the as-written prompt literal before committing the test (paren-safety, 2026-05-15 learning).
- `_cron-safe-commit.ts` uses relative `./_cron-shared` imports by convention (substrate-imports test skips `_`-prefixed files — do not cite it as the enforcer).
- Do not add `*/N` glob patterns inside JSDoc headers in cron files (terminates the comment, kills test collection — 2026-06-02 learning).
- `resolveOutputAwareOk`'s "trailing git push failure" comment block (`_cron-shared.ts:326-334`) references the old prompt behavior — update if touched, else accept comment-only drift.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6 — section complete above.
