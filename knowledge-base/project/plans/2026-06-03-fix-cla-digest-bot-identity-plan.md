---
title: "fix: CLA Assistant CI failure on automated community-digest PRs (digest bot identity)"
date: 2026-06-03
type: fix
branch: feat-one-shot-cla-digest-bot-identity
lane: cross-domain
status: draft
brand_survival_threshold: aggregate-pattern
requires_cpo_signoff: false
---

# fix: CLA Assistant CI failure on automated community-digest PRs

🐛 **Bug fix** — recurring `cla-check` FAILURE on every automated community-digest PR (e.g. PR #4907).

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** Decisions (precedent-diff), Research Insights (live-verification evidence)

### Key Improvements

1. **Precedent-diff gate (Phase 4.4):** confirmed the target identity (`github-actions[bot]` / `41898282+...@users.noreply.github.com`) is the *exact* canonical form already used by 12 sibling cron functions and is distinct from the agent push path's local identity — the fix adopts an established pattern, not a novel one.
2. **Live-verification evidence:** every cited PR/issue (#4907 OPEN, #4899 MERGED, #4870 MERGED), commit (9cd62804 ancestor-of-main, 17c6afd4 = digest commit), CLA action SHA pin (`ca4a40a7…`), and the load-bearing DB-ID claim (`github-actions[bot]` = 41898282, type Bot) resolved live at deepen time.
3. **Halt gates 4.6/4.7/4.8/4.9 all pass:** User-Brand Impact present (threshold `aggregate pattern`), Observability 5-field schema complete with non-SSH discoverability test, no PAT-shaped variables, no UI surface.

### New Considerations Discovered

- The fix relies on GitHub resolving the `41898282+github-actions[bot]@users.noreply.github.com` noreply email → DB ID 41898282. This is the same resolution the 12 sibling crons already depend on and that `cla-evidence` exercises today; if GitHub ever changes noreply→account mapping, failure mode and detection are captured in `## Observability`.
- No defense was *relaxed* by this change — the global default moves from a never-clearing identity (`soleur@localhost`) to an always-clearing one (`github-actions[bot]`); strictly an improvement in CLA outcome with no new ceiling to name.

## Overview

The daily `cron-community-monitor` Inngest function opens a community-digest PR. Its digest commit is authored by `Soleur <soleur@localhost>` — an identity with **no GitHub login**. The `cla-check` workflow (`contributor-assistant/github-action@v2.6.1`, `.github/workflows/cla.yml`) resolves PR authors via GraphQL `commit.author.user.login`; `soleur@localhost` maps to no contributor, so it can never match the allowlist (`dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot]`) and the check fails. The PR is then stuck — and the standard "comment to sign the CLA" remediation cannot work, because `soleur@localhost` has no GitHub account to attribute a signature to.

The fallback identity originates at `apps/web-platform/Dockerfile:137`:

```dockerfile
RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"
```

The cron prompt (`apps/web-platform/server/inngest/functions/cron-community-monitor.ts:181-182`) *attempts* to override this with a repo-LOCAL `git config user.name "github-actions[bot]"` / email `41898282+github-actions[bot]@users.noreply.github.com`. But that is **free-text prose instruction to the spawned `claude`**, not deterministic code. When the model skips or reorders that step, the commit falls back to the Dockerfile global identity → CLA fails. The failure is structural, not transient: the fix must make the *default* safe rather than depend on the prompt step firing.

### Primary fix

Change the Dockerfile global identity to `github-actions[bot]` / `41898282+github-actions[bot]@users.noreply.github.com`:

```dockerfile
RUN git config --global user.name "github-actions[bot]" \
    && git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

**Why this clears CLA unconditionally.** `contributor-assistant/github-action` (pinned at `ca4a40a7d1004f18d9960b404b97e5f30a505a08`) hardcode-drops committers whose `databaseId === 41898282` (the GitHub Actions bot) **before** the allowlist filter runs (`src/graphql.ts` → `filteredCommitters = committers.filter((c) => c.id !== 41898282)`). The `41898282+...@users.noreply.github.com` noreply email resolves to the `github-actions[bot]` account (verified: `gh api /users/github-actions%5Bbot%5D` → `{"id":41898282,"login":"github-actions[bot]","type":"Bot"}`). So a digest commit authored under this identity is dropped before the allowlist check ever runs — it clears CLA **even when the prompt's local `git config` step is skipped**.

Source of truth for the hardcode-drop mechanism: `knowledge-base/project/learnings/2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md`.

## Research Reconciliation — Spec vs. Codebase

All cited premises were verified against the live repo and GitHub API at plan time. No stale premises.

| Claim (from task) | Reality (verified) | Plan response |
|---|---|---|
| Dockerfile:137 sets `Soleur / soleur@localhost` global identity | Confirmed verbatim at `apps/web-platform/Dockerfile:137` | Edit this line (primary fix) |
| cron prompt sets local github-actions[bot] as free-text | Confirmed at `cron-community-monitor.ts:181-182`, inside a markdown prompt block (prose) | Keep as defense-in-depth (see Decisions) |
| CLA action hardcode-drops DB ID 41898282 before allowlist | Confirmed in learning 2026-04-27; `gh api` confirms `github-actions[bot]` id = 41898282, type Bot | Load-bearing — the fix relies on it |
| PR #4907 cla-check is failing; other checks pass | Confirmed: PR OPEN, `cla-check` = FAILURE, all ~45 other checks SUCCESS/SKIPPED | Unblock via Phase 2 |
| Offending commit is `soleur@localhost` with no login | Confirmed: commit `17c6afd4` author `Soleur / soleur@localhost`, login = NONE. The two later commits (`6f4ee3aa`, `47139593`) are `deruelle` (allowlisted) | Close-and-regenerate recommended (Phase 2) |
| Concierge per-user/per-repo credentialing (9cd62804 / #4899) might regress | **No regression.** #4899 injects GIT_ASKPASS *auth tokens*, not author identity. The agent commit/push path `apps/web-platform/server/push-branch.ts:99-110` sets its OWN local identity `Soleur Agent <agent@soleur.ai>` (`AGENT_AUTHOR_NAME`/`AGENT_AUTHOR_EMAIL`) before pushing; local config overrides global | Document non-regression; no code change to Concierge |

## User-Brand Impact

**If this lands broken, the user experiences:** automated community-digest PRs continue to sit with a red `cla-check`, blocking auto-merge; internal-ops only — no prospect or authenticated-user surface is touched.

**If this leaks, the user's data/workflow is exposed via:** N/A — the change alters only the git author *identity string* on internal-ops commits. No user data, secret, or PII is involved. (Sensitive-path scope-out: `threshold: aggregate pattern, reason: change is an internal-ops git-identity default with no user-data, auth, schema, or secret surface.`)

**Brand-survival threshold:** aggregate pattern — a single failed digest PR costs nothing user-visible; the cost is operator toil + a permanently-red CI lane if left unfixed across many digests.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `apps/web-platform/Dockerfile:137` global git identity is `github-actions[bot]` / `41898282+github-actions[bot]@users.noreply.github.com`. Verify: `grep -n 'user.name "github-actions\[bot\]"' apps/web-platform/Dockerfile` returns 1 match AND `grep -c 'soleur@localhost' apps/web-platform/Dockerfile` returns 0. ✓ (1 / 0)
- [x] **AC2** — The cron prompt's defense-in-depth local `git config` (`cron-community-monitor.ts:181-182`) is **retained unchanged** (kept as belt-and-suspenders; see Decisions). Verify: `grep -c '41898282+github-actions\[bot\]@users.noreply.github.com' apps/web-platform/server/inngest/functions/cron-community-monitor.ts` returns ≥ 1. ✓ (1)
- [x] **AC3** — Concierge non-regression documented: `apps/web-platform/server/push-branch.ts` still sets `AGENT_AUTHOR_NAME`/`AGENT_AUTHOR_EMAIL` locally (no edit). Verify: `grep -n 'AGENT_AUTHOR_NAME\|AGENT_AUTHOR_EMAIL' apps/web-platform/server/push-branch.ts` returns the constant defs + the two `git config` calls (4 matches). ✓ (4)
- [x] **AC4** — Docker image still builds: `docker build` of `apps/web-platform` succeeds through the modified `RUN git config` layer (or, if local Docker is unavailable, the line is a single static-string `git config` with no shell interpolation — visually verified no injection surface). The Dockerfile change is a pure literal swap. ✓ (pure literal swap, no interpolation; backslash-continued multi-line RUN is valid Docker syntax)
- [x] **AC5** — PR body uses `Ref #4907` (not `Closes #4907`): the digest PR is unblocked operationally (Phase 2), not auto-closed by this code PR's merge. If Phase 2's chosen action is "close #4907", that closure is an explicit post-merge step, not a `Closes` trailer.

### Post-merge (operator / automated)

- [ ] **AC6** — The new container image carrying the Dockerfile change is deployed to prod. The `web-platform-release.yml` pipeline rebuilds + restarts the container on every merge to `main` touching `apps/web-platform/**` (path-filtered `on.push`) — so **the merge IS the deploy**. Verify the deploy completed via the read-only deploy-status webhook at `deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access auth; credentials read-only), or by the release workflow's own success conclusion.
- [ ] **AC7** — Next community-digest PR (natural `0 8 * * *` UTC fire, or `cron/community-monitor.manual-trigger`) opens with `cla-check` = SUCCESS. This is the **real** validation: `cla.yml` runs under `pull_request_target`, so it executes the BASE-branch (`main`) workflow file — pre-merge probes against this branch are vacuous (per learning 2026-04-27). Verify post-deploy on the next digest PR's check rollup.
- [ ] **AC8** — PR #4907 is resolved per the Phase 2 decision (closed-and-regenerated, OR author-amended + force-pushed + cla-check green). No digest PR remains stuck on `cla-check`.

## Implementation Phases

### Phase 1 — Primary fix (Dockerfile global identity)

1. Edit `apps/web-platform/Dockerfile:137`:
   - **Before:** `RUN git config --global user.name "Soleur" && git config --global user.email "soleur@localhost"`
   - **After:** `RUN git config --global user.name "github-actions[bot]" \`
     `    && git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"`
2. Confirm no other site references `soleur@localhost` (already verified: only `Dockerfile:137` + this plan/learnings prose). The `sentry.client.config.ts:68` and `test/*.integration.test.ts` `user.email` hits are unrelated (Supabase auth-user email, not git identity).
3. Satisfies AC1, AC4.

### Phase 2 — Immediate unblock for PR #4907

**Recommendation: close #4907 and let the next (fixed) digest regenerate.** Rationale:
- The offending commit `17c6afd4` is the *first* of three commits on the branch, with two `deruelle` commits stacked on top. Amending its author requires a history rewrite (`git rebase`/`filter-branch`) + force-push of a bot-generated branch — higher-risk and higher-toil than regeneration.
- The cron itself is already fixed (#4870 raised `--max-turns` 50→80); a fresh digest will regenerate on the next `0 8 * * *` fire **once the Phase 1 image is deployed** (AC6). The regenerated PR inherits the github-actions[bot] global identity → clears CLA (AC7).
- The digest is idempotent daily content — no information is lost by closing #4907 and taking the next day's digest.

Steps:
1. After Phase 1 merges AND the new image is deployed (AC6), close PR #4907 with a comment referencing this fix: `gh pr close 4907 --comment "Closing — superseded by the CLA bot-identity fix (Dockerfile global identity → github-actions[bot]). The next community-digest PR will regenerate with a CLA-clearing author. See <this-PR>."`
2. Do NOT use `Closes #4907` in this code PR's body (the closure is gated on deploy, not merge) — use `Ref #4907` (AC5).

**Alternative (if the operator prefers to keep #4907):** amend the digest commit author and force-push:
```
git -C <checkout-of-branch> rebase -i 17c6afd4^  # reword author of 17c6afd4
# OR, surgically:
git -C <checkout> filter-branch --env-filter '
  if [ "$GIT_COMMIT" = "17c6afd4..." ]; then
    export GIT_AUTHOR_NAME="github-actions[bot]"
    export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
  fi' -- ci/community-digest-2026-06-03-203008
git push --force-with-lease origin ci/community-digest-2026-06-03-203008
```
Then re-trigger `cla-check` (push triggers `pull_request_target: synchronize`). This path is **not recommended** — history rewrite of a bot branch for content that regenerates daily is net-negative toil. Record the chosen path in the ship message.

Satisfies AC8.

### Phase 3 — Verification

1. Verify Phase 1 greps (AC1, AC2, AC3) pass on the branch.
2. After merge + deploy (AC6), observe the next digest PR's `cla-check` rollup = SUCCESS (AC7).
3. Confirm no digest PR stuck on `cla-check` (AC8).

## Decisions

- **Keep the prompt-level `git config` as defense-in-depth (recommended, do NOT simplify).** All 12 sibling cron functions set the same local github-actions[bot] identity — seven via prompt prose (`cron-seo-aeo-audit`, `cron-competitive-analysis`, `cron-growth-audit`, `cron-campaign-calendar`, `cron-growth-execution`, `cron-content-generator`, `cron-community-monitor`) and five via deterministic `spawnGitChecked` code (`cron-weekly-analytics`, `cron-compound-promote`, `cron-rule-prune`, `cron-content-vendor-drift`, `cron-content-publisher`). Removing it from `cron-community-monitor` alone would create inconsistency with its siblings AND remove a working override for the (rare) case where local config is desired over the global. The prompt step is now redundant-but-harmless: when the model executes it, identity is correct; when skipped, the new global default is *also* correct. Belt-and-suspenders is the right call here. (If a follow-up wants to retire the prompt steps cohort-wide now that the global is safe, that is a separate, larger PR — file as a deferral, do not fold in.)
- **PR #4907 unblock: close-and-regenerate over author-amend** (Phase 2). Lower risk, lower toil, no information loss.
- **No Concierge change.** `push-branch.ts` sets its own local identity; the global default swap does not reach it.

### Precedent-Diff (Phase 4.4) — pattern is established, not novel

The chosen identity is the canonical bot-author form already used across the cron cohort. `git grep -l` for the email literal across `apps/web-platform/server/inngest/functions/*.ts` returns 12 sibling sites that set exactly `github-actions[bot]` / `41898282+github-actions[bot]@users.noreply.github.com` as a **local** repo config before committing:

| Site | Mechanism | Scope |
|---|---|---|
| `cron-community-monitor.ts:181-182` | prompt prose (free-text → unreliable) | local |
| `cron-seo-aeo-audit.ts:112-113`, `cron-competitive-analysis.ts:132-133`, `cron-growth-audit.ts:93-94`, `cron-campaign-calendar.ts:92-93`, `cron-growth-execution.ts:120-121`, `cron-content-generator.ts:97-98` | prompt prose | local |
| `cron-weekly-analytics.ts:271-272`, `cron-compound-promote.ts:590-591`, `cron-rule-prune.ts:298-304`, `cron-content-vendor-drift.ts:540-546`, `cron-content-publisher.ts:350-354` | `spawnGitChecked(["config", ...])` (deterministic code) | local |
| **`Dockerfile:137` (this fix)** | `git config --global` (deterministic build layer) | **global default** |
| `push-branch.ts:99-110` (agent push) | `execFileSync("git", ["config", ...])` with `AGENT_AUTHOR_NAME`/`EMAIL` | local (`Soleur Agent <agent@soleur.ai>` — distinct, intentional) |

Diff vs precedent: this fix sets the **same canonical identity** the cron cohort already uses, but at the **global** layer so it becomes the safe *default* (the cron prompt steps remain as local-scope defense-in-depth). The only site with a deliberately *different* identity is `push-branch.ts` (the Concierge/agent path), which sets its own local identity and is therefore unaffected by the global swap — confirming the #4899 non-regression. **No novel pattern is introduced; the fix moves an already-canonical value to a more robust scope.**

## Domain Review

**Domains relevant:** Engineering (infra/CI) only.

No cross-domain (Product/UX, Legal, Marketing, Growth) implications — this is an internal-ops git-identity default change with no user-facing surface, no schema, no auth flow, and no regulated-data surface. GDPR gate (2.7) skipped: no regulated-data surface touched and none of the (a)-(d) expansion triggers fire (the change does not add LLM processing, does not declare single-user threshold, adds no cron, adds no artifact-distribution surface — it only changes the author string on an existing internal-ops commit).

## Infrastructure (IaC)

**Not applicable as a Terraform change.** The fix edits a `Dockerfile` `RUN` layer that is already part of the `apps/web-platform` image build. No new server, secret, vendor account, DNS record, cron, or persistent runtime process is introduced. The apply path is the existing `web-platform-release.yml` container rebuild + restart on merge to `main` (path-filtered `apps/web-platform/**`). No operator SSH and no secret mutation — the merge IS the apply (AC6).

## Observability

```yaml
liveness_signal:
  what: "cron-community-monitor digest PR opens with cla-check = SUCCESS"
  cadence: "daily (0 8 * * * UTC)"
  alert_target: "Sentry monitor WEB-PLATFORM-1Z (existing output-aware heartbeat on the cron)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-community-monitor.ts (heartbeat) + .github/workflows/cla.yml (check)"
error_reporting:
  destination: "GitHub Checks API (cla-check conclusion on the digest PR) + existing cron Sentry heartbeat"
  fail_loud: "cla-check FAILURE is visible on every digest PR rollup; the cron heartbeat already alerts on no-digest-produced. A re-failure of cla-check post-fix is directly observable on the next digest PR without SSH."
failure_modes:
  - mode: "github-actions[bot] noreply email stops resolving to DB ID 41898282 (GitHub-side change)"
    detection: "next digest PR cla-check = FAILURE despite the Dockerfile fix"
    alert_route: "GitHub Checks rollup on the digest PR (visible to operator on PR view)"
  - mode: "Dockerfile change not deployed (image not rebuilt)"
    detection: "digest commit still authored soleur@localhost; cla-check FAILURE"
    alert_route: "deploy-status webhook at deploy.soleur.ai/hooks/deploy-status + cla-check rollup"
logs:
  where: "GitHub Actions run logs for cla-check; commit author visible via `gh pr view <N> --json commits`"
  retention: "GitHub default (90 days for Actions logs)"
discoverability_test:
  command: "gh pr view <next-digest-PR> --json statusCheckRollup --jq '.statusCheckRollup[] | select(.name==\"cla-check\") | .conclusion'"
  expected_output: "SUCCESS"
```

## Files to Edit

- `apps/web-platform/Dockerfile` (line 137 — primary fix; the only code change)

## Files to Create

- None.

## Open Code-Review Overlap

None — no open `code-review` scope-out touches `apps/web-platform/Dockerfile`. (Single-file infra change; checked the planned edit path against open review issues.)

## Sharp Edges

- **`pull_request_target` runs the BASE-branch workflow.** `cla.yml` fires under `pull_request_target`, so it executes the version of the workflow on `main`, not on the PR branch. Pre-merge validation of the CLA outcome on *this* branch is therefore vacuous; the real proof is observing the next digest PR's `cla-check` after the image deploys (AC7). Do not claim "CLA verified" from any pre-merge run on this branch.
- **The merge does not immediately fix #4907.** The Dockerfile change only affects *newly built* images, hence *future* digest commits. Already-open PR #4907 carries the old `soleur@localhost` commit and must be resolved separately (Phase 2). Conflating the two ("merge fixes #4907") is wrong — use `Ref #4907`, not `Closes`.
- **The identity is an author string, not push auth.** `github-actions[bot]` as commit *author* on a feature branch does not change how the branch is pushed; push auth comes from the installation token in the cron flow (and the agent push path uses its own token). Swapping the author string does not alter push permissions.
- A plan whose `## User-Brand Impact` section is empty or placeholder will fail `deepen-plan` Phase 4.6. This section is filled (threshold: aggregate pattern, with sensitive-path scope-out reason).

## References

- `knowledge-base/project/learnings/2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md` — the hardcode-drop (DB ID 41898282) mechanism and the GraphQL-vs-REST bot-identity surface distinction.
- `knowledge-base/engineering/operations/post-mortems/cron-community-monitor-max-turns-exhaustion-postmortem.md` — the sibling cron incident (#4870 max-turns fix) that already restored digest production; this plan fixes the *next* failure that surfaces once digests resume.
- `.github/workflows/cla.yml` — the failing check (`contributor-assistant/github-action@v2.6.1`, allowlist + DB-ID drop).
- `apps/web-platform/server/push-branch.ts:27-28,99-110` — Concierge/agent local author identity (`Soleur Agent <agent@soleur.ai>`); proves the global-default swap does not regress #4899.
- Commit `9cd62804` (#4899) — Concierge GIT_ASKPASS credentialing (auth tokens, not author identity).
