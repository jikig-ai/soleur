---
title: "fix: hosted ship clone deepen, kb-index DIRTY race, markdown-lint gc race"
type: fix
date: 2026-09-14
slug: fix-ship-clone-kbindex-mdlint
branch: feat-one-shot-8091-8116-8117-clone-kbindex-mdlint
issue: 8091
closes: "8091, 8116, 8117"
priority: p2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

# fix: hosted ship clone deepen, kb-index DIRTY race, markdown-lint gc race

## Overview

Restore three independent operator-machinery invariants in one PR:

1. Hosted `/soleur:ship --headless` (`event-ship-merge` → `setupEphemeralWorkspace`) must have a merge-base for `origin/main...HEAD` after checking out a PR whose branch point is behind the depth-1 clone tip.
2. When GitHub reports `mergeStateStatus=DIRTY` and a local `git merge origin/main` is clean (the kb-index merge driver, or a stale GitHub cache), ship Phase 7 and `sync-pr-behind.sh` must sync and push rather than halt as a manual conflict.
3. `scripts/markdown-lint.test.sh` must not flake when git's detached `gc --auto` deletes loose objects while `cp -a` snapshots the sandbox.

These are operator-machinery bugs. Brand-survival is `none` (no Soleur end-user path). Target-user impact of landing them is restored hosted-ship Phase 5.5 and fewer operator sync-merge loops.

## Research Insights

### Premise Validation

Checked 2026-09-14 against `origin/main` and GitHub:

- Issues 8091, 8116, 8117 are OPEN with empty `closedByPullRequestsReferences`.
- `_cron-claude-eval-substrate.ts` still clones with `"--depth=1"` (verified `git grep` on `origin/main`). No `--deepen`/`--unshallow` in `event-ship-merge.ts` or the substrate file.
- `setupEphemeralWorkspace` is exported at that substrate file and is the clone chokepoint for the claude-eval fleet, including `event-ship-merge` (`cronName: "event-ship-merge"`).
- `.gitattributes` still has `knowledge-base/INDEX.md merge=kb-index` and `knowledge-base/kb-tags.txt merge=union`.
- `sync-pr-behind.sh` keys strictly on `BEHIND`; a non-BEHIND status (including `DIRTY`) prints "no sync needed" and exits 0.
- `scripts/markdown-lint.test.sh` still `git init && git add -A && git commit` then `cp -a "$SANDBOX/." "$PRISTINE/"` with no `gc.auto`.
- ADR-099 **rejects** collapsing the agent-workspace clone away from `git clone --depth 1`. ADR-210 **accepts** a local regenerating merge driver for committed `INDEX.md` and **rejects** "stop committing the generated artifacts entirely" as larger than that change's scope.
- `soleur:trigger-cron` allowlist is `EXPECTED_CRON_FUNCTIONS` via `manualTriggerEventFor` → `cron/<name>.manual-trigger`. `ship-merge.manual-trigger` is **not** on that list. Hosted verification cannot use trigger-cron as currently written.

Nothing cited was stale. The trigger-cron claim in the issue body is a verification-path imprecision, not a closed-issue premise.

### Property List

1. After `gh pr checkout` in hosted ship-merge, `git merge-base origin/main HEAD` succeeds for a PR whose branch point is older than the shallow tip.
2. `mergeStateStatus=DIRTY` plus a locally-clean merge of `origin/main` results in a fetch/merge/push, not a halt that asks for manual resolution.
3. Building the markdown-lint mutation sandbox never fails because auto-gc deleted `.git/objects/XX` during `cp -a`.

### Cut List

- **Substrate-wide `--filter=blob:none` in `setupEphemeralWorkspace`.** Buys property 1 (and 60 other `origin/main...HEAD` sites) but contradicts ADR-099 (depth-1 is the correct agent-sandbox shape), enlarges `.git` under the low-disk warn (192 MB depth-1 vs 607 MB full, measured in the issue), and would lazy-fetch blobs during `git diff` **inside** the containment hook. Ship-merge-only `git fetch --unshallow` after checkout runs via host-side `spawnSimple` (not the agent sandbox) and restores hosted Phase 5.5.
- **Stop committing `INDEX.md` on feature branches / regenerate on main.** Buys "GitHub never sees an INDEX.md conflict" but reverses ADR-210's committed-artifact model, touches the lefthook `generate-kb-index` write path, and needs a new post-merge owner for regenerate. Property 2 is the operator-loop halt; option 2 (DIRTY-but-locally-clean sync) buys it in the existing BEHIND machinery.
- **Merge queue.** Serialises the race; repo-settings change; not the cheapest fix.
- **Allowlist `ship-merge.manual-trigger` on trigger-cron.** Buys a no-SSH fire of hosted ship. Not a property in the list; expanding the trigger-secret blast radius (ship-merge labels PRs and runs `/soleur:ship`) is a new mechanism. Pre-merge proof is a hermetic git fixture of the merge-base invariant.

### Relevant file paths

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `setupEphemeralWorkspace` clone `"--depth=1"`; `spawnSimple` (stdout ignored, stderr capped); `warnIfCronWorkspaceLowOnDisk` is non-fatal.
- `apps/web-platform/server/inngest/functions/event-ship-merge.ts` — `checkout-pr` step is `spawnSimple("gh", ["pr", "checkout", ...])` then `spawnClaudeEval`. Empty `CRON_BASH_ALLOWLISTS["event-ship-merge"]` (deny-all bash inside the agent) is irrelevant: unshallow is host-side.
- `apps/web-platform/test/server/inngest/event-ship-merge.test.ts` — source-shape anchors, not behavioral clone tests.
- `plugins/soleur/scripts/sync-pr-behind.sh` — BEHIND-only; DIRTY no-ops.
- `plugins/soleur/lib/pr-merge-poll.ts` — `shouldResyncBeforePoll` is BEHIND-only; `isDirtyPollState` exists but is unused for resync.
- `plugins/soleur/skills/ship/SKILL.md` — fenced Phase 7 poll block exits on `*DIRTY*`; BEHIND auto-syncs. Fence must stay in lockstep with `plugins/soleur/skills/merge-pr/SKILL.md` and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (scenario 4 asserts DIRTY **exit**).
- `scripts/markdown-lint.test.sh` — `build_sandbox` git commit then `cp -a`. CI wiring is `.github/workflows/pr-quality-guards.yml` (asserted by W1e in the same suite).
- `lefthook.yml` `generate-kb-index` still **writes** INDEX.md on feature commits (property of option 1, not this PR).
- Precedent for `gc.auto=0`: `apps/web-platform/infra/git-data-bootstrap.sh` and `scripts/followthroughs/ccla-representative-icla-7922.sh` (`git -c gc.auto=0`).

### Institutional learnings

- 2026-09-09: GitHub `DIRTY` is a cache. Three of four DIRTY reports on one PR were stale; `git merge-tree --write-tree` returned rc=0. `sync-pr-behind.sh` no-ops on that state. Discriminator is merge-tree, not `mergeStateStatus`.
- 2026-09-08 ADR-210: local driver cannot run on GitHub's merge; `--check` is the unregistered-driver backstop. Stopping committing INDEX.md was recorded as a challenge, not adopted.
- Mid-2026 clone-shape change in the same substrate file (rm+symlink of `plugins/soleur`) made clone-git see every tracked plugin file as DELETED (654-file contamination). Bounded verification after unshallow: working tree not dirty; plugin files not all deleted.
- 2026-07-29: `git fetch --unshallow` is the documented way to restore history-reading diagnostics on a shallow clone.

### CLAUDE.md / constitution

Minimalism ladder: stop at the first rung that holds. Ship-merge-only unshallow is one spawnSimple after an existing checkout. DIRTY handling reuses the BEHIND merge/push. `gc.auto=0` is one config line. Shell scripts: `set -euo pipefail`, `local`, stderr for errors, stdout for operator-protection signals (`[pr-behind-sync]` already goes to stdout).

### Research Reconciliation — Spec vs. Codebase

| Claim | Reality on origin/main | Plan response |
|---|---|---|
| trigger-cron fires hosted ship-merge | Allowlist is cron-only; event is `ship-merge.manual-trigger` | Do not expand the allowlist. Pre-merge AC is a hermetic git fixture. Hosted human-readable form is the next natural `event-ship-merge` run after deploy. |
| Substrate-wide clone-shape change is similarly cheap | ADR-099 forbids it; disk 192 vs 607 MB; blob fetches need network in the hook | Ship-merge-only unshallow after checkout. |
| Option 1 (INDEX.md off feature branches) is ~60 lines | Also fights ADR-210 and needs a post-merge regenerate owner | Option 2: DIRTY-but-locally-clean sync. |
| `sync-pr-behind.sh` is the only DIRTY site | Ship Phase 7 poll **exits** on DIRTY; Grok uses the script; Claude uses the fenced poll | Edit script + poll block + merge-pr mirror + fixture together. |
| Scenario 4 of the poll fixture stays valid | Default `git()` mock returns 0, so a DIRTY-then-merge-tree-clean arm would **sync**, not exit | Split: real-conflict DIRTY still exits; locally-clean DIRTY syncs. Override `git merge-tree` in the real-conflict scenario. |

### Community Discovery / Functional Overlap

TypeScript + bash, both covered by built-in agents. No uncovered stack. No community skill replaces hosted-clone deepen, GitHub DIRTY handling, or a fixture `gc.auto` pin. Skipped install.

### External research

Skipped. Strong local patterns (ADR-099, ADR-210, BEHIND sync, `gc.auto=0` precedent). Not a security/payments/privacy topic.

## Problem Statement / Motivation

Hosted ship on any incident-signal PR that is not the newest on main halts at Phase 5.5 with `SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=2` because `git diff origin/main...HEAD` has no merge-base on a depth-1 clone. Before the structural-enumeration seat (merged 2026-09) the same empty listing was read as "No match" and the headless arm looped authoring duplicate PIRs.

Every PR that adds a KB file races GitHub's server-side merge (no `kb-index` driver) against local clean merges. Auto-merge never fires on DIRTY. Measured 2026-09-12: five sync-merges before land; `test-scripts` is the long pole.

The required `markdown-lint` mutation suite flakes when git auto-gc races `cp -a`. A required check going red on an unrelated PR is an operator halt.

## Proposed Solution

**#8091 — ship-merge only.** After successful `gh pr checkout` in `event-ship-merge.ts` `checkout-pr`, `spawnSimple("git", ["fetch", "--unshallow", "origin"], { cwd: workspace.spawnCwd })`. Then `spawnSimple("git", ["merge-base", "origin/main", "HEAD"], { cwd })`. Non-zero on either throws (Inngest step fails, existing `reportSilentFallback` `op: "ship-merge-pipeline"`). Log `{ fn, prNumber, mergeBaseOk: true }` on success (pino → Sentry breadcrumb). Do **not** change `--depth=1` in `setupEphemeralWorkspace`.

**#8116 — DIRTY-but-locally-clean like BEHIND.** In `sync-pr-behind.sh` and the Phase 7 poll block: on `BEHIND` **or** `DIRTY`, `git fetch origin main`, then `git merge-tree --write-tree origin/main HEAD`. rc=0 → `git merge origin/main --no-edit` + `git push` (existing BEHIND path). rc≠0 → existing "merge conflict — manual resolution required" / `[ship.phase7.dirty]` exit. `shouldResyncBeforePoll` returns true for DIRTY as well as BEHIND. Admin-merge hatch stays BEHIND-only (GitHub refuses `--admin` on a PR it has computed unmergeable).

**#8117 — disable auto-gc in the fixture repo.** Immediately after `git init` in `build_sandbox`: `git config gc.auto 0`. `restore()` copies `$PRISTINE`, which is not a live git repo, so it needs nothing.

## Technical Considerations

- Unshallow is host-side `spawnSimple` (stdout ignored). `git merge-base` exit code is the probe; do not need the SHA in the spawn result.
- Authenticated clone URL remains `origin`; `git fetch --unshallow origin` uses the same token-bearing remote as the clone.
- Low-disk guard is warn-only. Unshallow cost is paid only by ship-merge, once per run.
- Phase 7 poll fence: any DIRTY-arm edit must update `merge-pr/SKILL.md` and `ship-phase-7-poll-fixtures.test.sh` in the same change. The fixture's default `git()` returns 0; a locally-clean DIRTY would otherwise look like a successful merge-tree and take the sync path.
- Hosted ship Phase 7 runs inside the ephemeral clone, which does **not** register `merge.kb-index.driver` (SessionStart/`prepare` are not the Inngest spawn path). Without the driver, `git merge-tree` matches GitHub's default text merge: a true INDEX.md conflict stays rc≠0 and takes the dirty-exit; a stale DIRTY (no content conflict) is rc=0 and syncs. Operator worktrees have the driver, so INDEX.md DIRTY-but-locally-clean syncs. Do not add driver install to the substrate in this PR.
- `cq-write-failing-tests-before`: each bug's RED tests land before its GREEN edit.
- NFR: availability of hosted ship (operator), not end-user latency.

## Files to Edit

- `apps/web-platform/server/inngest/functions/event-ship-merge.ts` — unshallow + merge-base probe after `gh pr checkout`.
- `apps/web-platform/test/server/inngest/event-ship-merge.test.ts` — source-shape anchors for `--unshallow` and `merge-base`.
- `plugins/soleur/scripts/sync-pr-behind.sh` — DIRTY (and BEHIND) → merge-tree discriminator → merge/push or exit 6.
- `plugins/soleur/lib/pr-merge-poll.ts` — `shouldResyncBeforePoll` true for DIRTY.
- `plugins/soleur/test/pr-merge-poll.test.ts` — RED then GREEN for DIRTY resync.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 DIRTY arm: merge-tree-clean → BEHIND path; real conflict still exits. Update the DIRTY-exit prose outside the fence to match.
- `plugins/soleur/skills/merge-pr/SKILL.md` — fenced poll mirror.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — split scenario 4; add locally-clean DIRTY sync scenario.
- `scripts/markdown-lint.test.sh` — `git config gc.auto 0` after `git init`.

## Files to Create

- `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` — hermetic git fixture for property 1 (synthesized repo, no network).
- `plugins/soleur/test/sync-pr-behind.test.sh` — hermetic fixture for DIRTY-clean vs DIRTY-conflict vs BEHIND vs CLEAN.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (65 issues) contained none of the planned paths.

## Implementation Phases

TDD order is load-bearing. Do not implement a GREEN edit before its RED tests fail.

### Phase 0: Setup (shared)

- Confirm worktree CWD and branch.
- Reproduce #8091 locally against this repo: `git clone --depth=1` of a file:// copy that has a branch point below the tip, fetch that branch, `git merge-base origin/main HEAD` exits 1. This is the fixture shape Phase 1 will encode, not a product edit.

### Phase 1: #8117 markdown-lint gc race (smallest, independent)

**RED**

- Add an assertion in `build_sandbox` (or immediately after it, before `cp -a`) that `git -C "$SANDBOX" config --get gc.auto` is `0`. On origin/main this fails (no config). Keep it in the suite so a future delete of the pin is red.

**GREEN**

- In `build_sandbox`, after `git init -q` and before `git add`/`git commit`: `git config gc.auto 0`.
- Re-eval: `grep -c 'gc.auto' scripts/markdown-lint.test.sh` ≥ 1.
- Run `bash scripts/markdown-lint.test.sh` (this is the required CI surface; `test-all.sh` deliberately does not register it).

### Phase 2: #8091 hosted ship merge-base

**RED**

- Write `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh`:
  1. Synthesize a repo with ≥3 commits on `main`, a branch from commit 1, one commit on the branch.
  2. `git clone --depth=1` the `main` tip into a workdir; fetch the branch and check it out (the `gh pr checkout` analogue).
  3. Assert `git merge-base origin/main HEAD` fails (the defect).
  4. Run the **prescribed** command sequence (`git fetch --unshallow origin` then `git merge-base origin/main HEAD`).
  5. Assert merge-base succeeds **and** `git status --porcelain` is empty (contamination bound; the 654-file class).
- Add event-ship-merge source-shape tests expecting `--unshallow` and `merge-base` in the handler source. These fail until GREEN.
- Drop the new file at `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh`. `scripts/test-all.sh` `SUITE_GLOBS` already includes `plugins/soleur/test/*.test.sh` (verified on origin/main); no runner edit.

**GREEN**

- In `event-ship-merge.ts` `checkout-pr`, after a successful `gh pr checkout`, same `cwd`/`env` as the checkout spawn:
  1. `spawnSimple("git", ["fetch", "--unshallow", "origin"], { cwd })`. Exit 0 → continue. Non-zero whose stderr contains `complete repository` (already not shallow; `gh pr checkout` may have deepened) → continue. Any other non-zero → throw with `redactToken(stderr)`, same shape as clone-failure. Do not switch on `rev-parse --is-shallow-repository`: `spawnSimple` discards stdout.
  2. Always then `spawnSimple("git", ["merge-base", "origin/main", "HEAD"], { cwd })`. Exit ≠ 0 → throw `no merge-base origin/main HEAD after unshallow`.
  3. `logger.info({ fn: FUNCTION_NAME, prNumber, mergeBaseOk: true }, "ship-merge workspace has origin/main...HEAD merge-base")`.
- Do not edit `_cron-claude-eval-substrate.ts` clone args.
- Re-eval (event-grep): `git grep -cE -- '--deepen|--unshallow' apps/web-platform/server/inngest/functions/event-ship-merge.ts` ≥ 1.

**Bounded contamination check (same suite):** after unshallow, `git diff --name-only` is empty; `plugins/soleur` is not reported as wholesale deleted.

### Phase 3: #8116 DIRTY-but-locally-clean

**RED** (write all of these before any GREEN)

- `pr-merge-poll.test.ts`: change "shouldResyncBeforePoll fires only on BEHIND" so a new assertion expects DIRTY true. This fails on origin/main.
- `sync-pr-behind.test.sh`: four cases against a mocked `gh pr view` + real git repos:
  1. `OPEN CLEAN` → exit 0, no merge (today).
  2. `OPEN BEHIND` + clean merge-tree → merge+push (today's path; keep).
  3. `OPEN DIRTY` + merge-tree rc=0 → merge+push (fails today: "no sync needed").
  4. `OPEN DIRTY` + merge-tree rc≠0 → exit 6, merge aborted (fails today: no-ops instead of declaring conflict).
- `ship-phase-7-poll-fixtures.test.sh`: keep scenario 4 as **real conflict** by overriding `git merge-tree` to return 1; still expect `[ship.phase7.dirty]`. Add scenario 4b: DIRTY + merge-tree rc=0 → `BEHIND detected` / `auto-sync` / no dirty-exit. 4b fails until the poll block changes.

**GREEN**

- `shouldResyncBeforePoll`: true for `BEHIND` or `DIRTY`.
- `sync-pr-behind.sh`: treat `*BEHIND*` **or** `*DIRTY*` as sync-needed. After fetch, run `git merge-tree --write-tree origin/main HEAD >/dev/null`. Non-zero → print conflict paths, `git merge --abort` if needed, exit 6. Zero → existing merge --no-edit + push. Structured stdout must still contain `[pr-behind-sync]` and `auto-sync` so AwaitShell patterns keep matching. Add a `DIRTY` token so the issue re-eval `grep -c DIRTY` ≥ 1.
- Phase 7 poll DIRTY arm (ship + merge-pr mirror): fetch + merge-tree; rc=0 → set state as BEHIND and fall through to the existing BEHIND auto-sync (counts against `MAX_BEHIND_SYNCS`); rc≠0 → existing dirty exit. Do **not** route DIRTY into the admin-merge hatch.
- Re-eval: `grep -c 'DIRTY' plugins/soleur/scripts/sync-pr-behind.sh` ≥ 1.

### Phase 4: Tests / typecheck

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` if event-ship-merge.ts changed (not `npm run -w`).
- Plugin tests: `bun test plugins/soleur/test/pr-merge-poll.test.ts` and the new `.test.sh` files via the repo's existing plugin-test runner.
- `bash scripts/markdown-lint.test.sh`.
- `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Substrate `--filter=blob:none` | ADR-099; disk; network-in-hook; 26 callers. |
| `git fetch --deepen=N` | N may be less than the branch age; `--unshallow` is the sure merge-base. |
| Stop committing INDEX.md on feature branches | ADR-210 rejected stop-committing; needs a new main-side regenerate owner; larger than the DIRTY sync. |
| Merge queue | Repo-settings; not cheapest. |
| trigger-cron carve-out for `ship-merge.manual-trigger` | Expands a mutating-event allowlist; not required to prove the git invariant. |

No deferred item in this table needs a tracking issue: the cuts are rejected, not postponed.

## User-Brand Impact

- **If this lands broken, the user experiences:** no Soleur end-user artifact. Operators see hosted ship halt at Phase 5.5, or a required markdown-lint flake, or a DIRTY auto-merge stall — the same class as today.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure. Unshallow uses the existing installation-token clone URL already used for `git clone`. DIRTY sync pushes the same merge origin/main already used for BEHIND. Fixture `gc.auto=0` is a test-sandbox config.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the diff touches apps/web-platform/server/inngest (sensitive-path regex) only to deepen an already-authenticated ephemeral clone used by hosted ship; no tenant data, auth, or billing path changes.`

## Observability

```yaml
liveness_signal:
  what: "Inngest function event-ship-merge run (id event-ship-merge) plus required GitHub check markdown-lint"
  cadence: "per hosted ship-merge invocation; markdown-lint on every PR"
  alert_target: "Sentry web-platform via reportSilentFallback; GitHub required-check failure on markdown-lint"
  configured_in: "apps/web-platform/server/inngest/functions/event-ship-merge.ts (inngest.createFunction id event-ship-merge); scripts/required-checks.txt row markdown-lint"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN; reportSilentFallback op ship-merge-pipeline / clone-failure shape"
  fail_loud: "Inngest step checkout-pr throws; function returns { ok: false, reason: pipeline-error }; existing ship/failed label path unchanged"
failure_modes:
  - mode: "git fetch --unshallow origin fails (network/auth)"
    detection: "spawnSimple non-zero; thrown Error with redacted stderr; Inngest sentry-correlation middleware tags inngest.fn_id=event-ship-merge (layer 1) and reportSilentFallback op ship-merge-pipeline (layer 2 pino breadcrumb + capture)"
    alert_route: "Sentry issue on web-platform; Inngest run failed"
  - mode: "merge-base still missing after unshallow"
    detection: "in-step git merge-base origin/main HEAD exit 1 (host-side probe in checkout-pr, not a host-only boolean); throw; layer 1 sentry-correlation + layer 2 pino logger"
    alert_route: "Sentry; Inngest run failed. Discriminator field mergeBaseOk=false vs unshallow exit in the thrown message"
  - mode: "working tree dirty after unshallow (plugin-file contamination class)"
    detection: "hermetic suite hosted-ship-shallow-merge-base.test.sh asserts git status --porcelain empty; CI plugin tests (layer 6 workflow run log)"
    alert_route: "required test check red"
  - mode: "DIRTY reported but local merge-tree is clean and sync does not run"
    detection: "sync-pr-behind.sh stdout lacks auto-sync on OPEN DIRTY; CLI path is cli-stdout-artifact (layer 7) with durable producer plugins/soleur/scripts/sync-pr-behind.sh; hosted ship path is the same script or Phase 7 poll inside claude-eval, stderrTail on spawnResult to Sentry (layer 1) when ship exits non-zero"
    alert_route: "ship Phase 7 still prints [ship.phase7.dirty] on a locally-clean tree; fixture 4b red"
  - mode: "markdown-lint.test.sh cp -a race (gc deleted objects)"
    detection: "CI job markdown-lint in pr-quality-guards.yml (layer 6 workflow run log); FATAL: pristine snapshot failed"
    alert_route: "required markdown-lint check red"
logs:
  where: "Inngest run payload extra + Sentry (pino hooks.logMethod); GitHub Actions job log for markdown-lint; [pr-behind-sync] lines on stdout"
  retention: "Sentry project retention; GitHub Actions logs per repo policy"
discoverability_test:
  command: "bash -c 'grep -cE -- \"--unshallow|--deepen\" apps/web-platform/server/inngest/functions/event-ship-merge.ts; grep -c DIRTY plugins/soleur/scripts/sync-pr-behind.sh; grep -c gc.auto scripts/markdown-lint.test.sh'"
  expected_output: "three positive integer lines (each >= 1)"
```

No SSH. First token `bash` is on the probe-verb allowlist.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Engineering assessment: follow ADR-099 and ADR-210; no new substrate, no tenancy move, no ADR amendment. Product/UX Gate: no UI-surface files in Files to Create/Edit; mechanical override does not fire. CTO-style note (in-process): the riskiest coupling is the Phase 7 poll fence + merge-pr mirror + fixture scenario 4 mock-git returning 0.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git grep -cE -- '--deepen|--unshallow' apps/web-platform/server/inngest/functions/event-ship-merge.ts` returns ≥ 1.
- [ ] AC2: `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` fails on a depth-1 clone of a branch-below-tip **before** unshallow, and passes after the prescribed `git fetch --unshallow origin` with empty `git status --porcelain`.
- [ ] AC3: `event-ship-merge.ts` `checkout-pr` throws when `git merge-base origin/main HEAD` is non-zero after unshallow (source contains `merge-base` next to the unshallow spawn).
- [ ] AC4: `_cron-claude-eval-substrate.ts` still contains `"--depth=1"` (substrate-wide clone shape unchanged).
- [ ] AC5: `grep -c 'DIRTY' plugins/soleur/scripts/sync-pr-behind.sh` ≥ 1 and the script, given `OPEN DIRTY` plus a locally-clean merge-tree, performs fetch/merge/push (fixture case 3).
- [ ] AC6: The same script, given `OPEN DIRTY` plus merge-tree rc≠0, exits 6 and does not push (fixture case 4).
- [ ] AC7: `shouldResyncBeforePoll("DIRTY")` is true; `shouldResyncBeforePoll("CLEAN")` remains false.
- [ ] AC8: `ship-phase-7-poll-fixtures.test.sh` scenario 4 (merge-tree fail) still matches `[ship.phase7.dirty]`; new scenario 4b (merge-tree ok) matches auto-sync and does not match the dirty-exit line. Mirror parity with `merge-pr/SKILL.md` still holds.
- [ ] AC9: Admin-merge hatch prose still says BEHIND only, not DIRTY (`BEHIND only, and not DIRTY` remains in ship/SKILL.md).
- [ ] AC10: `grep -c 'gc.auto' scripts/markdown-lint.test.sh` ≥ 1; `bash scripts/markdown-lint.test.sh` exits 0.
- [ ] AC11: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is green if the TS edit landed.

### Post-merge

- [ ] AC-PM1: After `apps/web-platform/server/inngest/functions/event-ship-merge.ts` is on the deployed image, the next `event-ship-merge` run whose PR is not the newest on main shows a `[PASS]` or `[FAIL]` line from `ship-pir-action-items-gate.sh --branch` in the transcript, not `SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=2` caused by missing merge-base. Fire path: wait for a natural qualifying run (trigger-cron does not allowlist `ship-merge.manual-trigger`). `Automation: not feasible via trigger-cron because MANUAL_TRIGGER_EVENTS is derived only from EXPECTED_CRON_FUNCTIONS; expanding it is a cut. Natural next run is the human-readable re-eval.`

No soak / time-gated close criterion — no follow-through enrollment.

## Test Scenarios

- Given a synthesized repo with a branch point below the shallow tip, when cloning `--depth=1` and checking out the branch, then `git merge-base origin/main HEAD` fails; after `git fetch --unshallow origin`, it succeeds and the worktree is clean.
- Given `event-ship-merge` source, when grepping for `--unshallow`, then the checkout-pr step contains it and the substrate clone still has `--depth=1`.
- Given `OPEN DIRTY` and merge-tree rc=0, when running `sync-pr-behind.sh`, then it merges and pushes.
- Given `OPEN DIRTY` and merge-tree rc≠0, when running `sync-pr-behind.sh`, then exit 6.
- Given Phase 7 poll scenario 4b, when GitHub says DIRTY and merge-tree is clean, then the loop auto-syncs instead of printing `[ship.phase7.dirty]`.
- Given `build_sandbox`, when `git config --get gc.auto` is read, then it is `0`, and `cp -a` of the sandbox succeeds.

## Success Metrics

- Hosted ship Phase 5.5 no longer halts with merge-base unavailable on non-newest PRs (AC1–AC4, AC-PM1).
- Operator DIRTY-but-locally-clean loops collapse to the existing BEHIND sync (AC5–AC9).
- Required markdown-lint mutation suite stops racing gc (AC10).

## Dependencies & Risks

- `git fetch --unshallow` duration/size on the ship-merge host. Mitigation: ship-only; low-disk warn already exists; fail-loud on unshallow error.
- Phase 7 fence drift. Mitigation: existing mirror-parity fixture; edit all three files together.
- Default git mock in poll fixtures returns 0. Mitigation: Phase 3 RED splits scenario 4.
- Unshallow contamination of the plugin tree. Mitigation: porcelain-empty assertion in the hermetic suite.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Do not cite closed issue/PR numbers in `closes:` or Closes lines beyond 8091, 8116, 8117.
- `spawnSimple` ignores stdout; merge-base success is the exit code.
- Do not `git add -A`. Do not stash.

## SpecFlow Analysis

Hosted-ship and operator-worktree DIRTY paths diverge on merge-driver registration (see Technical Considerations). Additional edges folded into phases:

- Unshallow on an already-complete repo must continue, not throw (Phase 2 GREEN arm).
- Phase 7 DIRTY-clean fallthrough must not double-count a second fetch failure as a new DIRTY exit on the same tick: after merge-tree rc=0, fall through to the BEHIND arm on this iteration (set `s` to `OPEN BEHIND`) rather than `break` and wait 60s.
- `sync-pr-behind.sh` `OPEN CLEAN` / `OPEN BLOCKED` remain no-ops (auto-merge is waiting on checks, not on a sync).
- `restore()` in markdown-lint.test.sh copies `$PRISTINE`; with `gc.auto=0` the snapshot is stable; no gc config needed on restore.

## Scoped Advisor Consult

Riskiest phase: #8116 poll-block + fixture mock-git. Guidance applied: split DIRTY into merge-tree-clean vs real-conflict **in the RED tests first**; do not let scenario 4's default `git()` return 0 silently convert a real-conflict test into a sync test. Do not expand trigger-cron. Do not change substrate `--depth=1`.

## Architecture Decision (ADR/C4)

Skipped. Bug fixes on existing surfaces. ADR-099 and ADR-210 are followed, not amended. C4 actors/systems checked against `model.c4`, `views.c4`, `spec.c4`: founder/operator, GitHub, Inngest, and the plugin CLI are already modeled; no new actor, vendor, container, or access relationship. Cardinalities in edge prose are unchanged (no new cron monitor or heartbeat slug).

## References & Research

- ADR-099 git-surface topology (depth-1 agent workspace).
- ADR-210 regenerating merge driver for INDEX.md.
- `knowledge-base/engineering/operations/runbooks/ship-merge-trigger.md` (event `ship-merge.manual-trigger`).
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` layers 1–7.
