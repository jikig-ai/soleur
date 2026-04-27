# Fix: CLA allowlist uses wrong format for Claude bot identity

- **Issue:** [#2907](https://github.com/jikig-ai/soleur/issues/2907) (P2, `type/bug`)
- **Branch:** `feat-one-shot-2907`
- **Worktree:** `.worktrees/feat-one-shot-2907/`
- **Files to edit:** `.github/workflows/cla.yml` (one line)
- **Files to create:** none
- **Type:** `fix(ci)` / `semver:patch`
- **Detail level:** MINIMAL (one-line workflow edit; CI-only, no production code, no migration)

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** Overview, Research Reconciliation, Hypotheses, Risks, Phase 1 (recommendation flip)
**Research sources used:** direct inspection of `contributor-assistant/github-action` source on GitHub (`src/checkAllowList.ts`, `src/graphql.ts`, `src/interfaces.ts` at master), live GraphQL probes against jikig-ai/soleur commits 5eac2aae and 0a455f8c, GitHub REST `/users/claude[bot]` and `/orgs/jikig-ai/installations`, AGENTS.md `hr-never-fake-git-author` + linked learning `2026-04-24-fake-git-author-bare-repo-bot-override.md`, contributor-assistant README (web).

### Key improvements discovered during deepen pass

1. **The action checks `committer.name` populated from a GraphQL `user.login` lookup, not the raw display name.** Verified via direct read of `checkAllowList.ts`: `isUserNotInAllowList(committer.name)` does exact-string match (with `*` wildcard) against the allowlist. `getCommitters` in `graphql.ts` builds `name = committer.login || committer.name`, so the **GitHub login** is what's matched. For Claude-bot commits this is `claude[bot]`.
2. **Two distinct bot identities both display as `claude[bot]` — only one needs allowlisting.** Live GraphQL on commits in this repo confirmed:
   - **DB ID `209825114`, login `claude[bot]`** — the real Anthropic GitHub App. Used by `scheduled-bug-fixer` (`soleur:fix-issue` output, e.g. PR #2893). This is the identity the allowlist must cover.
   - **DB ID `41898282`, login `github-actions[bot]`** (display name `claude[bot]`) — the generic GitHub Actions runner with `user.name` overridden inside the workflow. Used by community-digest cron (PR #2898/#2899). The contributor-assistant action **hardcoded-filters** ID `41898282` in `getCommitters` (`filteredCommitters = committers.filter((c) => c.id !== 41898282)`) — these commits are auto-allowed regardless of allowlist content. That's why #2898 passed CLA, NOT because `github-actions[bot]` was on the allowlist.
3. **`app/claude` is dead code in the CLA allowlist.** The `app/<slug>` form is the GitHub **REST API**'s representation of an App as a PR-author (`gh pr view --json author --jq .author.login` returns `app/claude`). The contributor-assistant action does not use that surface — it uses GraphQL `commits.edges.node.commit.author.user.login`, which returns the login `claude[bot]` (not `app/claude`). The bare token `claude` matches no surface at all. The plan's prior "defense-in-depth" framing for `app/claude` was incorrect; both `app/claude` and `claude` are dead. Recommendation flipped: **remove both**, keep allowlist minimal.
4. **AGENTS.md `hr-never-fake-git-author` is the closely related rule.** The PR #2815 incident the rule covers is the inverse failure mode: a worktree config drift made `deruelle`-intended commits land as `test@test`, also tripping CLA. `worktree-manager.sh ensure_worktree_identity` is the structural fix. Issue #2907 is unrelated to that — it's about a real bot identity that legitimately cannot sign a CLA — but the connection is worth noting in the PR body so future maintainers don't conflate the two surfaces.
5. **Pre-merge probe is genuinely impossible without merging.** `pull_request_target` runs the workflow file from the BASE branch. The PR for #2907 will run the OLD allowlist on its own commits (which are authored by `deruelle`, allowlisted, so cla-check passes vacuously). Validation is post-merge only, on the next real `claude[bot]`-authored PR. Pre-merge: YAML parse + diff inspection.

### New considerations surfaced

- The allowlist's wildcard support (`bot*`) is a documented escape hatch but would be too permissive (matches any `*[bot]` username, including third-party apps). Not adopted; explicit `claude[bot]` is auditable and reviewable.
- If Anthropic ships a new GitHub App with a different login (rename, multi-app split), the failure surface is loud (`cla-check: fail` on the next bot PR) and the remediation is one-line. No need to over-design.
- The action's hardcoded ID-`41898282` filter is a load-bearing implicit allowlist. If `actions/checkout` ever changes its committer-injection ID, every workflow currently relying on the auto-filter will start failing CLA. Not an actionable risk for this PR but worth keeping in mind during future GitHub Actions runner version bumps.

## Overview

The `contributor-assistant/github-action` v2.6.1 enforces CLA signatures on every committer of a pull request. The allowlist in `.github/workflows/cla.yml:34` currently reads:

```yaml
allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude"
```

PRs authored by the Anthropic Claude GitHub App (DB ID `209825114`, login `claude[bot]`) — produced by `claude-code-action` and `soleur:fix-issue` — carry commits whose GraphQL-resolved committer login is `claude[bot]`. Neither `app/claude` nor the bare token `claude` matches that login on the surface the CLA action actually reads (see §Research Reconciliation for the source-code trace), so the CLA check fails on every such PR until the operator amends commit authorship to `deruelle` (which is allowlisted) — exactly the workaround applied to PR #2893.

The fix replaces the dead tokens `app/claude,claude` with the canonical `claude[bot]`. Both `app/claude` (a REST-API-only form the CLA action's GraphQL query never sees) and the bare `claude` (matches no surface) are removed in the same edit to keep the allowlist minimal and audit-clean. **Note:** `app/claude` is still load-bearing in `scheduled-bug-fixer.yml:213` and `bot-pr-with-synthetic-checks` because those workflows match against the REST API's PR-author surface (`gh pr view --json author`, which DOES return `app/claude`). Those usages are correct and unchanged — the `app/claude` removal here is scoped to `cla.yml` only.

## Research Reconciliation — Spec vs. Codebase

The issue body's premise is correct on the fix but slightly imprecise on the diagnosis. The deepen-pass nailed down the exact action-internal mechanism.

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Claude GitHub App's actual login is `claude[bot]`" | **Confirmed via three independent sources.** (1) `gh api /users/claude[bot]` returns `{login: "claude[bot]", id: 209825114, type: "Bot"}`. (2) Live GraphQL on commit `5eac2aae5...` returns `author.user.login = "claude[bot]", databaseId = 209825114`. (3) `git log --all --pretty='%an <%ae>'` on `main` shows every real Claude-bot commit emits the email `209825114+claude[bot]@users.noreply.github.com`. | Add `claude[bot]` to allowlist. |
| "`app/claude,claude` matches neither the bot's GitHub login nor any known format" | **Confirmed for the CLA action's surface.** Direct read of `contributor-assistant/github-action/src/checkAllowList.ts` and `src/graphql.ts` (on master) shows: the action queries `commits.edges.node.commit.author.user.login` via GraphQL, then matches `committer.login \|\| committer.name` against the allowlist via exact-string-equality (with `*` wildcard). GraphQL **never returns the `app/<slug>` form** — that form only appears in REST API responses for App PR-authors. So `app/claude` is genuinely dead in `cla.yml`. The bare `claude` token would only match a real human user with that exact login (no such match in this repo). | **Remove both `app/claude` and bare `claude` from `cla.yml`.** They are unreachable with the action's GraphQL surface. |
| "PR #2898 passed CLA because its commit was authored by `github-actions[bot]`" | **Confirmed but the mechanism is more specific than the issue states.** Live GraphQL on PR #2898 shows the commit's email is `41898282+claude[bot]@users.noreply.github.com` — GitHub resolves the `41898282` ID to login `github-actions[bot]` (display name `claude[bot]` for that commit because the workflow set `user.name`). The action's `getCommitters` then **hardcoded-filters out ID `41898282`** before any allowlist check (`filteredCommitters = committers.filter((c) => c.id !== 41898282)`). The PR clears CLA because the committer was dropped, not because `github-actions[bot]` was on the allowlist. | No change required, but documented here so the fix's reviewer doesn't conflate the two paths. The community-digest cron path (PR #2899) and any other workflow that emits commits via `actions/checkout`'s default identity will continue to bypass the allowlist via this hardcoded filter. |
| "PR #2893 evidence: cla-check failed for `claude[bot]` author" | **Confirmed via remediation trail.** PR #2893 currently shows `cla-check: SUCCESS` with a single commit authored by `deruelle` — i.e. authorship was force-rewritten as the issue describes. The original failure is no longer in `gh` (force-push erases prior commit SHAs) but the rewrite + the git-log evidence on `main` (10+ recent commits authored by ID `209825114`) corroborate the issue body's claim. | Post-merge validation will rerun the gate against an unrewritten `claude[bot]`-authored PR (next scheduled bug-fixer run, typically daily). |

**Action surface trace (from direct source read).** Pinned reference — `contributor-assistant/github-action@v2.6.1` (SHA `ca4a40a7d1004f18d9960b404b97e5f30a505a08` per `.github/workflows/cla.yml:26`):

```ts
// src/graphql.ts (committer extraction):
//   GraphQL pulls commit.author.user.login + databaseId
//   getCommitters builds: { name: committer.login || committer.name, id: committer.databaseId }
//   filteredCommitters = committers.filter((c) => c.id !== 41898282)  // <— github-actions[bot] auto-allowed

// src/checkAllowList.ts (allowlist match):
//   isUserNotInAllowList(committer.name) does pattern.split(',').filter(...)
//   Each pattern: if includes('*') → regex (escaped); else exact equality.
```

So the load-bearing entry is `claude[bot]` (matches `committer.login` for ID 209825114). Wildcard `bot*` would also work but is overpermissive. The action's auto-filter on ID 41898282 is undocumented in the README — discovered only by source read.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (21 open issues); no body matches `.github/workflows/cla.yml` or `claude[bot]`.

## Hypotheses (L7 only — no network/SSH symptom; gate `hr-ssh-diagnosis-verify-firewall` does not apply)

| Hypothesis | Verification | Status |
|---|---|---|
| Allowlist token `claude[bot]` will match the committer login the action checks | Direct source read of `src/graphql.ts` + `src/checkAllowList.ts` (master). Live GraphQL on commits 5eac2aae and 0a455f8c returns `author.user.login = "claude[bot]"` and `databaseId = 209825114`. The action does exact string match on `login \|\| name` against allowlist tokens. | **Confirmed** |
| Removing `app/claude` from `cla.yml` breaks another path | The CLA action's GraphQL surface never returns the `app/<slug>` form (that's REST API only). The three other repo locations that DO match `app/claude` (`scheduled-bug-fixer.yml:213`, `scripts/lint-bot-synthetic-completeness.sh:12`, `bot-pr-with-synthetic-checks/action.yml`) all run against the REST API (`gh pr view --json author`). They are unaffected by edits to `cla.yml`'s allowlist string. | **Safe to remove** |
| The `41898282` auto-filter is reliable enough to leave undocumented | The filter is hardcoded in `src/graphql.ts` — not a config knob. If the action upgrades majors and changes/removes the filter, every existing `actions/checkout`-default committer would start tripping CLA. Out of scope for this PR but recorded as a future risk. | **Note** |

## Implementation Phases

### Phase 1: Edit the allowlist

Single-line edit to `.github/workflows/cla.yml` line 34.

- [ ] Read `.github/workflows/cla.yml` (already read at plan time; re-read pre-edit per `hr-always-read-a-file-before-editing-it`).
- [ ] Apply this exact edit:

    ```diff
    -          allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,app/claude,claude"
    +          allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot]"
    ```

    Net change: replace `app/claude,claude` with `claude[bot]`. Both removed tokens are unreachable on the action's GraphQL surface (see Research Reconciliation source-trace block); the new token matches `committer.user.login` for the real Claude GitHub App (DB ID `209825114`).

- [ ] Verify YAML is still parseable: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cla.yml'))"` — must exit 0.
- [ ] Confirm `app/claude` matchers in OTHER workflow files (`scheduled-bug-fixer.yml:213`, `scripts/lint-bot-synthetic-completeness.sh:12`, `bot-pr-with-synthetic-checks/action.yml`) are NOT touched — they operate on the REST API's PR-author surface and are correct as-is. Quick sanity grep after edit: `grep -rn 'app/claude' .github/ scripts/` should still return ≥3 hits in those non-cla.yml files and ZERO hits in `cla.yml`.

### Phase 2: Verify on a real bot-authored PR (post-merge)

The fix only matters when a `claude[bot]`-authored PR runs the CLA workflow. We cannot fully validate pre-merge because:

1. `pull_request_target` triggers on the **base branch's** workflow file — pre-merge, the base (`main`) still has the broken allowlist, so a feature-branch PR runs the old config.
2. The CLA check on this PR (#2907's PR) will run with the **new** config from `main` only after merge.

The cheap pre-merge proxy is YAML-parse + diff inspection (Phase 1). The load-bearing post-merge probe is:

- [ ] Post-merge: monitor the next `soleur:fix-issue`-generated PR (the scheduled bug-fixer runs daily; `gh pr list --author 'app/claude' --state open --limit 5` shows recent ones).
- [ ] Confirm `gh pr checks <N> | grep cla-check` reports `pass` without authorship rewriting.
- [ ] If the next bot-fix PR is generated within 48h of merge: explicit verification.
- [ ] If no bot-fix PR is generated within 48h: the daily community-digest cron (also `claude[bot]`-authored, e.g. PR #2899) is a sufficient probe; capture the same `cla-check: pass` evidence from one of its CI runs.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/cla.yml` line 34 contains `claude[bot]` and no longer contains `app/claude` or the bare token `claude`.
- [ ] `grep -n 'app/claude' .github/workflows/cla.yml` returns zero hits; `grep -rn 'app/claude' .github/ scripts/` returns ≥3 hits in other files (`scheduled-bug-fixer.yml`, `bot-pr-with-synthetic-checks/action.yml`, `lint-bot-synthetic-completeness.sh`) — those are correct usages on the REST API surface and must remain.
- [ ] YAML parses cleanly (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cla.yml'))"` exits 0).
- [ ] PR body contains `Closes #2907`.
- [ ] No other files modified (only `.github/workflows/cla.yml` shows in `git status --short`).

### Post-merge (operator)

- [ ] First post-merge `claude[bot]`-authored PR (bot-fix or community digest) shows `cla-check: pass` without commit-authorship rewriting.
- [ ] If the post-merge probe fails: open a follow-up issue immediately documenting the failing committer login (from `git log` on the failing PR's commit) and re-evaluate the allowlist token.

## Test Strategy

No automated tests. The CLA workflow is itself the integration test, and its trigger surface (`pull_request_target` against `main`) cannot be exercised from a feature branch — see Phase 2 rationale. The pre-merge gate is YAML validity; the post-merge gate is a real bot-PR run.

This is consistent with the project convention for `.github/workflows/*.yml` single-line config edits — the merged branches `2026-03-19-chore-cla-ruleset-integration-id-plan.md` and `2026-03-20-chore-standardize-claude-code-action-sha-plan.md` followed the same pattern (no unit tests for YAML edits; production observation is the validator).

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `claude[bot]` is not the actual committer login the contributor-assistant action keys on | NEGLIGIBLE (post-deepen) | Direct source read of `src/checkAllowList.ts` + `src/graphql.ts` (master) confirmed exact-string match against `committer.login \|\| committer.name`. Live GraphQL on real Claude-bot commits in this repo (5eac2aae, 0a455f8c) confirmed `login = "claude[bot]"`. REST API `/users/claude[bot]` confirmed canonical login. Three independent confirmations. |
| Removing `app/claude` from `cla.yml` breaks a CLA path | NEGLIGIBLE | The action's GraphQL never returns `app/<slug>`. The form is REST API-only. The three other repo files matching `app/claude` are unrelated to the CLA workflow's allowlist. |
| Removing the bare `claude` token breaks something | NEGLIGIBLE | The bare token matches no real login. `git log -p .github/workflows/cla.yml` shows it was added speculatively alongside `app/claude` and never tested against a real PR. |
| Future Anthropic GitHub App rename changes the bot's login | MEDIUM (out of scope) | If Anthropic ships a new App, `claude[bot]` would change. Detection: `cla-check: fail` on the next bot-PR. Remediation: one-line edit. Not worth a wildcard `*[bot]` pattern (would weaken the allowlist's audit trail). |
| Pre-merge probe gives false confidence | MEDIUM | Phase 2 explicitly documents this: pre-merge YAML-parse is necessary but not sufficient. The load-bearing acceptance criterion is post-merge observation on the next real `claude[bot]`-authored PR. |
| The `41898282` auto-filter in the action is undocumented and could change | LOW | If the action's major bumps and the filter is removed, every `actions/checkout`-default committer would start tripping CLA. We pin to `@v2.6.1` SHA, so this is a future-when-we-bump risk only. Track via `.github/dependabot.yml` if it covers third-party actions; otherwise revisit during the next CLA-action bump PR. |

## Non-Goals

- Switching to a wildcard pattern (`*[bot]`) — too permissive; weakens the audit trail.
- Adding `claude` (bare display-name) — not a GitHub login; matches no surface.
- Restructuring how the contributor-assistant action is invoked (action version, params other than allowlist) — not in scope.
- Updating the `app/claude` matchers in `scheduled-bug-fixer.yml` / `bot-pr-with-synthetic-checks/action.yml` — those operate on the GitHub PR-author REST surface (`gh pr view --json author`) which still returns `app/claude`. They are correct as-is.

## Domain Review

**Domains relevant:** none

This is an infrastructure/CI-only change (one line in a GitHub Actions workflow). No user-facing surface, no product or marketing implications, no legal change (the CLA document and signature flow are unchanged — only the allowlist that bypasses the flow for pre-approved bot identities is corrected). No domain leader gate fires.

## Files to Edit

- `.github/workflows/cla.yml` — line 34 only.

## Files to Create

- None.

## PR Body Reminder

```
Closes #2907

Replaces dead allowlist tokens `app/claude,claude` with `claude[bot]` (the actual
GitHub committer login Anthropic's Claude GitHub App emits, DB ID 209825114).

Why both removals: direct read of `contributor-assistant/github-action@v2.6.1`
source (`src/graphql.ts` + `src/checkAllowList.ts`) shows the action queries
`commit.author.user.login` via GraphQL and does exact-string match against the
allowlist. GraphQL never returns the `app/<slug>` form (REST-API-only) and no
real GitHub user has the bare login `claude` — both tokens are unreachable on
the action's surface.

The `app/claude` matchers in `scheduled-bug-fixer.yml`, `bot-pr-with-synthetic-
checks`, and `lint-bot-synthetic-completeness.sh` are unaffected — they operate
on the REST API's PR-author surface where `app/claude` IS the correct match.

Pre-merge validation: YAML parse + grep audit. Post-merge validation: next
real `claude[bot]`-authored PR (scheduled bug-fixer, daily) clears `cla-check`
without commit-authorship rewriting.

Related: AGENTS.md `hr-never-fake-git-author` (PR #2815) — that rule covers
the inverse failure (worktree config drift makes operator commits look like
bot commits and trips CLA). #2907 is the legitimate-bot path that simply
needs allowlisting.
```
